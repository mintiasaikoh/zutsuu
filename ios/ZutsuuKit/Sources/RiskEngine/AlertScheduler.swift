import Foundation

/// 通知を出さない時間帯。端末ローカル時刻の壁時計で判定する。
/// 既定は 22:00〜08:30（設計書 §4）。ユーザーが変更できる。
///
/// `start > end` のときは日付をまたぐ区間として扱う。
/// `start == end` は幅ゼロ、すなわち「静穏時間なし」と定義する。
public struct QuietHours: Sendable, Equatable {
    /// 開始時刻（22.0 = 22:00）。0 以上 24 未満。
    public let start: Double
    /// 終了時刻（8.5 = 08:30）。0 以上 24 未満。この時刻ちょうどは静穏時間に含まない。
    public let end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    /// 静穏時間として機能するか。
    ///
    /// 非有限値や範囲外は設定を読み違えた実装バグ。デバッグでは停止させ、
    /// リリースでは「静穏時間なし」に倒す。ここを素通りさせると
    /// NaN の比較が全て false になって静穏時間が黙って無効化され、
    /// 深夜に通知が鳴る。`Scoring.swift` の `isFinite` ガードと同じ理由。
    public var isEnabled: Bool {
        guard start.isFinite, end.isFinite,
              (0..<24).contains(start), (0..<24).contains(end) else {
            assertionFailure("QuietHours の値が不正: start=\(start), end=\(end)")
            return false
        }
        return start != end
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled else { return false }
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
        return start > end ? (hour >= start || hour < end) : (hour >= start && hour < end)
    }

    /// `date` 以降で最初に静穏時間が明ける時刻。`date` が静穏時間内でない場合は `date` 自身。
    ///
    /// 壁時計上の時刻へ移動するので `addingTimeInterval` ではなくカレンダー演算を使う。
    /// 日付をまたぐ静穏時間では終了時刻が翌日に来るため、
    /// `date` と同じ日の end を組み立てると 1 日前の時刻になってしまう。
    /// 夏時間で存在しない時刻に当たった場合は `.nextTime` が直後の実在時刻へ送る。
    func firstMomentOutside(_ date: Date, calendar: Calendar) -> Date? {
        guard contains(date, calendar: calendar) else { return date }
        let hour = Int(end.rounded(.down))
        let minute = Int(((end - Double(hour)) * 60).rounded())
        return calendar.nextDate(after: date,
                                 matching: DateComponents(hour: hour, minute: minute),
                                 matchingPolicy: .nextTime,
                                 direction: .forward)
    }
}

/// 予約する 1 件のローカル通知。
/// アプリ層はこの `fireDate` をそのまま `UNNotificationRequest` のトリガに渡す。
/// 「発火すべきでない」理由は全て `AlertScheduler` 側で落としてあるので、
/// アプリ層が時刻を再検査する必要はない。
public struct ScheduledAlert: Sendable, Equatable {
    /// 通知を発火させる時刻。必ず `targetDate` より前で、静穏時間の外。
    public let fireDate: Date
    /// リスクが閾値を超える時刻（エピソードの入口）。通知本文の「何時から」。
    public let targetDate: Date
    /// 最高レベルに最初に到達した時点の判定。
    /// 通知本文で要因（気圧・湿度・気温）を出し分けるために持たせている。
    public let assessment: RiskAssessment

    /// エピソード中に到達する最高レベル。
    /// `assessment` から導出する。二重に持つと食い違い得るため格納しない。
    public var targetLevel: RiskLevel { assessment.level }

    public init(fireDate: Date, targetDate: Date, assessment: RiskAssessment) {
        self.fireDate = fireDate
        self.targetDate = targetDate
        self.assessment = assessment
    }
}

/// リスク曲線から通知予約時刻を算出する。
/// サーバーを持たず端末上で先に予約する設計（設計書 §4）の中核。
public struct AlertScheduler: Sendable {
    /// 症状発現の何分前に通知するか。設計書 §4 の「1〜2時間前」の中央値。
    public static let leadTime: TimeInterval = 90 * 60

    /// これ以上のレベルへ上がる場合のみ通知する。
    public static let threshold: RiskLevel = .caution

    /// 発火時刻が既に過ぎている場合に `now` から先へ送る幅。
    /// `UNTimeIntervalNotificationTrigger` は間隔が正でないと例外を投げるため、
    /// 0 ではなく僅かに未来を指す必要がある。
    public static let grace: TimeInterval = 60

    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// リスク曲線から通知予約のリストを作る。
    ///
    /// 閾値以上が続く区間を 1 つのエピソードとして扱い、1 件だけ通知する。
    /// 上昇のたびに拾うと、1 回の荒天で「注意」「危険」と連投になる。
    /// エピソードの入口を `targetDate`、区間中の最高レベルを `targetLevel` とする。
    /// 途中で悪化する場合に最初から最高レベルを名乗ることになるが、
    /// 通知の役目は早く動いてもらうことなので、控えめに言うより良いと判断した。
    /// 詳細は画面側で読める。
    ///
    /// 曲線の先頭から既に閾値以上の場合は通知しない。
    /// 既に起きている事象であり、画面に出ている情報を通知で繰り返しても価値がない。
    ///
    /// - Note: `risks` は時刻の昇順かつ等間隔であることを前提とする。検証はしない。
    ///   生成元は `RiskAnalyzer.analyze` のみで、どちらも同関数が保証している。
    public func schedule(_ risks: [HourlyRisk], now: Date,
                         quietHours: QuietHours?) -> [ScheduledAlert] {
        episodes(in: risks).compactMap { alert(for: $0, now: now, quietHours: quietHours) }
    }

    /// 閾値以上が連続する区間。
    private struct Episode {
        /// 閾値を最初に超えた時刻。リードタイムはここから逆算する。
        let onsetDate: Date
        /// 区間中の最高レベルに最初に到達した時点の判定。
        var peak: RiskAssessment
        /// 閾値未満から上がって入った区間か。曲線の先頭から始まる区間は false。
        let isRise: Bool
    }

    private func episodes(in risks: [HourlyRisk]) -> [Episode] {
        var result: [Episode] = []
        var current: Episode?

        for (index, risk) in risks.enumerated() {
            let assessment = risk.assessment
            guard assessment.level >= Self.threshold else {
                if let episode = current, episode.isRise { result.append(episode) }
                current = nil
                continue
            }
            if var episode = current {
                if assessment.level > episode.peak.level { episode.peak = assessment }
                current = episode
            } else {
                current = Episode(onsetDate: risk.point.date,
                                  peak: assessment,
                                  isRise: index > 0)
            }
        }
        if let episode = current, episode.isRise { result.append(episode) }
        return result
    }

    /// 1 エピソードを 1 件の予約に落とす。予約すべきでなければ nil。
    private func alert(for episode: Episode, now: Date, quietHours: QuietHours?) -> ScheduledAlert? {
        let targetDate = episode.onsetDate

        // 規則 1: 既に起きた事象は予約しない。
        // 効果としては規則 3・5 に含まれる（過ぎた対象は発火が `now + grace` へ
        // 繰り上がり、必ず対象時刻以降になって規則 5 で落ちる）。
        // 意図を明示するために残しているだけで、ここが唯一の防波堤ではない。
        guard targetDate > now else { return nil }

        // 規則 2: 既定のリードタイム。
        // 経過時間そのものなので絶対時刻演算でよい（夏時間の影響を受けない）。
        var fireDate = targetDate.addingTimeInterval(-Self.leadTime)

        // 規則 3: 発火時刻が過ぎていれば直後に鳴らす。破棄しないのは、
        // 差し迫った上昇こそ最も知らせる価値があるため。
        if fireDate <= now { fireDate = now.addingTimeInterval(Self.grace) }

        // 規則 4: 静穏時間に掛かる発火は明けまで繰り下げる（破棄しない）。
        // 繰り上げ（規則 3）より後に置くことが仕様。逆順にすると、
        // 静穏時間が leadTime より短い設定（例: 13:00〜13:30 の昼寝）で
        // `now + grace` が静穏時間内に落ちて鳴る。
        // 最後に繰り下げることで「静穏時間内に鳴らさない」が常に成り立つ。
        //
        // 就寝中に到来する事象（例: 03:00 の上昇）は、繰り下げ先が対象時刻を
        // 追い越して規則 5 で落ちる。一方 23:00 の上昇は発火 21:30 が静穏時間の
        // 外なので繰り下げが起きず、就寝前に予告できる。
        // 「対象時刻が静穏時間内なら破棄」という規則を別に置くと後者まで消える。
        if let quietHours {
            guard let moved = quietHours.firstMomentOutside(fireDate, calendar: calendar) else {
                return nil
            }
            fireDate = moved
        }

        // 規則 5: リードタイムが残っていない通知は価値がない。
        guard fireDate < targetDate else { return nil }

        return ScheduledAlert(fireDate: fireDate, targetDate: targetDate,
                              assessment: episode.peak)
    }
}
