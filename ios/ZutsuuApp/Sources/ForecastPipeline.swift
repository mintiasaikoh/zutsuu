// /Users/mymac/zutsuu/ios/ZutsuuApp/Sources/ForecastPipeline.swift
// 位置取得 → WeatherKit → リスク解析 → 通知予約 → 体調記録の一巡を束ねる。
// 画面と OS サービスの間に 1 つの状態源を置き、再スケジュールの経路を一本化するため。
// 関連: WeatherProvider.swift, NotificationClient.swift, CheckInStore.swift, docs/appcore-api.md §3
import Foundation
import Observation
import OSLog
import AppCore
import KiabouUI
import PersonalRisk
import RiskEngine

@MainActor @Observable
final class ForecastPipeline {
    private(set) var risks: [HourlyRisk] = []
    private(set) var swing: TemperatureSwing?
    private(set) var lastUpdated: Date?
    private(set) var errorMessage: String?
    private(set) var isRefreshing = false
    private(set) var attribution: WeatherAttribution?
    /// 予約した通知のうち発火が最も早いもの。ホームの「次の通知」に、通知と同じ文面で出す。
    private(set) var nextAlert: AlertNotificationContent?
    /// 記録のある暦日の累計。記録の見返り表示に使う。
    private(set) var recordedDays = 0
    /// Watch へ送る要約の出口。予報更新と記録のたびに呼ぶ（Plan 5）。
    var watchContextSink: ((WatchContext) -> Void)?

    private var series: [WeatherPoint] = []
    private var coordinate: Coordinate?
    private let store: CheckInStore
    private let weather: any WeatherProviding
    private let location: LocationProvider
    private let notifications: NotificationClient
    /// 同梱の平年値テーブル。読めなければ暫定の `NeutralClimatology`（絶対気圧 0pt）へ倒し、ログに残す。
    private let climatology: any PressureClimatology = {
        do { return try ReanalysisClimatology.bundled() } catch {
            ForecastPipeline.logger.error("平年値テーブルを読めません: \(String(describing: error), privacy: .public)")
            return NeutralClimatology()
        }
    }()

    init(store: CheckInStore,
         weather: any WeatherProviding = WeatherKitProvider(),
         location: LocationProvider = LocationProvider(),
         notifications: NotificationClient = NotificationClient()) {
        self.store = store
        self.weather = weather
        self.location = location
        self.notifications = notifications
    }

    /// 起動時・画面表示時に呼ぶ。直近 30 分以内に更新済みなら何もしない。
    func refreshIfStale() async {
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < 30 * 60 { return }
        await refresh()
    }

    /// 予報を取り直し、リスク曲線と通知予約を作り直す。
    ///
    /// 系列は昨日 00:00 から 72 時間先まで。寒暖差（昨日の最高気温）とリスク解析
    /// （72 時間の予報）を同じ 1 回の取得で賄う（`appcore-api.md` §2）。
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        errorMessage = nil
        do {
            let now = Date()
            let calendar = Calendar.current
            let coordinate = try await location.current()
            let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: now) ?? now)
            let end = now.addingTimeInterval(72 * 3600)
            let samples = try await weather.hourly(at: coordinate, from: start, to: end)

            self.coordinate = coordinate
            series = WeatherSeries.hourly(from: samples)
            // 解析のたびに生成する（Calendar を保持するため。riskengine-api.md §6.1）。
            let analyzer = RiskAnalyzer(climatology: climatology,
                                        coordinate: coordinate, calendar: calendar)
            risks = analyzer.analyze(series)
            swing = TemperatureSwingDetector.detect(in: series, now: now, calendar: calendar)
            lastUpdated = now
            recordedDays = (try? store.recordedDayCount(calendar: calendar)) ?? 0
            await rescheduleNotifications(now: now)
            publishWatchContext(now: now)
            if attribution == nil { attribution = try? await weather.attribution() }
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// `KiabouCheckInView(onRecord:)` に渡す。保存に成功したときだけ戻る。
    /// 記録時点の要因を一緒に保存し、その場で通知閾値を学習し直す。
    func record(_ checkIn: HealthCheckIn) async throws {
        try store.save(checkIn, risk: risk(at: checkIn.date))
        recordedDays = (try? store.recordedDayCount(calendar: .current)) ?? recordedDays
        await rescheduleNotifications(now: Date())
        publishWatchContext(now: Date())
    }

    /// Watch からの記録。iPhone と同じ保存経路（重複防止・再学習・再予約）を通す。
    func record(fromWatch checkIn: WatchCheckIn) async throws {
        guard let feeling = HealthFeeling(rawValue: checkIn.feeling) else { return }
        try await record(HealthCheckIn(id: checkIn.id, date: checkIn.date, feeling: feeling))
    }

    /// 今後 24 時間のレベルと次の通知の見出しだけを Watch へ渡す（設計書 §7.2 の線引き）。
    private func publishWatchContext(now: Date) {
        guard let sink = watchContextSink, !risks.isEmpty else { return }
        let hourly = upcoming.prefix(24).map {
            WatchContext.HourLevel(date: $0.point.date, level: $0.assessment.level)
        }
        sink(WatchContext(updatedAt: now, hourly: Array(hourly),
                          nextAlertTitle: nextAlert?.title, recordedDays: recordedDays))
    }

    /// 表示用の現在時刻のリスク。系列にその時刻がなければ nil。
    var current: HourlyRisk? { risk(at: Date()) }

    /// 現在時刻以降の曲線（画面の時間別一覧用）。
    var upcoming: [HourlyRisk] {
        let hourStart = Self.floorToHour(Date())
        return risks.filter { $0.point.date >= hourStart }
    }

    private func risk(at date: Date) -> HourlyRisk? {
        let hourStart = Self.floorToHour(date)
        return risks.first { $0.point.date == hourStart }
    }

    private static func floorToHour(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
    }

    /// 通知用の判定だけを個人化し、表示用の `risks` は汎用のまま（personalrisk-api.md §4）。
    private func rescheduleNotifications(now: Date) async {
        guard !risks.isEmpty else { return }
        let settings = AppSettings.load()
        let calendar = Calendar.current
        let model = PersonalRiskModel.fitted(
            to: (try? store.observations()) ?? [],
            prior: .prior(for: settings.sensitivities))
        let schedulingRisks = risks.map { risk in
            HourlyRisk(point: risk.point,
                       assessment: RiskAssessment(
                           level: model.schedulingLevel(for: risk.assessment.factors),
                           score: risk.assessment.score,
                           factors: risk.assessment.factors),
                       pressureChanges: risk.pressureChanges)
        }
        let alerts = AlertScheduler(calendar: calendar)
            .schedule(schedulingRisks, now: now, quietHours: settings.quietHours)
        nextAlert = alerts.min { $0.fireDate < $1.fireDate }
            .map { AlertNotifications.content(for: $0, risks: risks, calendar: calendar) }
        // 権限は最初に予約が必要になった時点で求める。未許可のまま add しても届かない。
        if await notifications.authorizationStatus() == .notDetermined {
            _ = await notifications.requestAuthorization()
        }
        let plan = NotificationReconciler.reconcile(pending: await notifications.pending(),
                                                    scheduled: alerts, now: now)
        await notifications.apply(plan, risks: risks, calendar: calendar)
        Self.logger.info("通知予約: 予定 \(alerts.count) 件、追加 \(plan.add.count) 件、取消 \(plan.cancel.count) 件")
    }

    private static func describe(_ error: any Error) -> String {
        switch error {
        case LocationError.denied:
            return "位置情報の利用が許可されていません。設定アプリから許可してください。"
        case LocationError.unavailable:
            return "現在地を取得できませんでした。下に引くともう一度試せます。"
        default:
            // WeatherKit の内部エラー名（JWT 認証など）はユーザーには意味がない。
            // 原因の切り分けはログで行う。
            Self.logger.error("予報の取得に失敗: \(String(describing: error), privacy: .public)")
            return "予報を取得できませんでした。しばらくしてからもう一度お試しください。"
        }
    }

    private static let logger = Logger(subsystem: "com.mintiasaikoh.zutsuu", category: "forecast")
}
