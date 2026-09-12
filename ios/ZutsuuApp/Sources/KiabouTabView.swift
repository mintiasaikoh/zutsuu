// /Users/mymac/zutsuu/ios/ZutsuuApp/Sources/KiabouTabView.swift
// きあぼうタブ。着せ替え・見え方の設定・記録ログの確認を行う。
// 記録の入口はホームに一本化し、このタブは相棒と過ごす場所にするため（Plan 3 Task 7）。
// 関連: ../../ZutsuuKit/Sources/KiabouUI/KiabouOutfit.swift, TodayView.swift, CheckInStore.swift
import SwiftUI
import SwiftData
import KiabouUI
import PersonalRisk

struct KiabouTabView: View {
    @Environment(ForecastPipeline.self) private var pipeline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("kiabou.scene") private var sceneID = KiabouScenery.cove.id
    @AppStorage("kiabou.native.dim") private var dim = false
    @AppStorage("kiabou.outfit") private var outfitID = KiabouOutfit.original.id
    @AppStorage("kiabou.pillow") private var pillowID = KiabouBedding.matchID
    @AppStorage("kiabou.blanket") private var blanketID = KiabouBedding.matchID
    @Query(sort: \CheckInRecord.date, order: .reverse) private var records: [CheckInRecord]

    private var palette: KiabouPalette { KiabouPalette(dim: dim) }
    /// 解放判定は @Query から直接数える。パイプラインの予報更新を待つと、
    /// 予報が取れるまで全部ロックに見えてしまう。
    private var recordedDays: Int {
        Set(records.map { Calendar.current.startOfDay(for: $0.date) }).count
    }
    /// 気象要因が付いた記録のある日数。相関レポートの準備完了はこちらで判定する（レビュー R20）。
    private var analysableDays: Int {
        Set(records.filter(\.hasFactors).map { Calendar.current.startOfDay(for: $0.date) }).count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    KiabouStage(resting: false, scenery: .scenery(id: sceneID), dim: dim,
                                moving: !reduceMotion && scenePhase == .active,
                                outfit: .outfit(id: outfitID))
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    outfitSection
                    beddingSection
                    scenerySection
                    appearanceSection
                    correlationSection
                    logSection
                }
                .padding(16)
            }
            .background(palette.page.ignoresSafeArea())
            .foregroundStyle(palette.ink)
            .tint(palette.primary)
            .navigationTitle("きあぼう")
        }
    }

    // MARK: - 着せ替え

    /// 解放は累計記録日数（設計書 §6.7）。次に選べるものは「あと N 日」で予告し、
    /// 派手な演出や記録を迫る文言は出さない。
    private var outfitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("きせかえ").font(.subheadline.weight(.semibold)).foregroundStyle(palette.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(KiabouOutfit.all) { outfit in
                    outfitCell(outfit)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private func outfitCell(_ outfit: KiabouOutfit) -> some View {
        unlockCell(name: outfit.name, requiredDays: outfit.requiredDays,
                   selected: outfit.id == outfitID, selectedLabel: String(localized: "いまの姿")) { outfitID = outfit.id }
    }

    // MARK: - 寝具

    /// 枕・毛布の色系統。かすみ・しずく・こもれびの姿で休むときだけ効く（kiabou-integration.md §3.2）。
    private var beddingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ねどこ").font(.subheadline.weight(.semibold)).foregroundStyle(palette.muted)
            beddingRow(String(localized: "まくら"), selection: $pillowID)
            beddingRow(String(localized: "もうふ"), selection: $blanketID)
            if KiabouOutfit.outfit(id: outfitID).family == nil {
                Text("まくらと毛布は、かすみ・しずく・こもれびの姿で休むときに使われます。")
                    .font(.caption).foregroundStyle(palette.muted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private func beddingRow(_ title: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(palette.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                ForEach(KiabouBedding.choices) { choice in
                    unlockCell(name: choice.name, requiredDays: choice.requiredDays,
                               selected: choice.id == selection.wrappedValue, selectedLabel: String(localized: "いまの\(title)")) {
                        selection.wrappedValue = choice.id
                    }
                }
            }
        }
    }

    // MARK: - 背景

    /// 解放は着せ替えと同じ累計記録日数（kiabou-integration.md §3.3）。無地と入り江は最初から。
    private var scenerySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("はいけい").font(.subheadline.weight(.semibold)).foregroundStyle(palette.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(KiabouScenery.all) { scenery in
                    unlockCell(name: scenery.name, requiredDays: scenery.requiredDays,
                               selected: scenery.id == sceneID, selectedLabel: String(localized: "いまの背景")) {
                        sceneID = scenery.id
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 20))
    }

    /// 着せ替え・背景で共用する選択セル。ロック中は「あと N 日」の予告だけを出す。
    @ViewBuilder
    private func unlockCell(name: String, requiredDays: Int, selected: Bool,
                            selectedLabel: String, select: @escaping () -> Void) -> some View {
        let unlocked = recordedDays >= requiredDays
        Button {
            if unlocked { select() }
        } label: {
            VStack(spacing: 4) {
                Text(name).font(.subheadline.weight(selected ? .bold : .regular))
                if !unlocked {
                    Text("あと\(requiredDays - recordedDays)日")
                        .font(.caption.monospacedDigit()).foregroundStyle(palette.muted)
                } else if selected {
                    Text(selectedLabel).font(.caption).foregroundStyle(palette.muted)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(selected ? palette.primary.opacity(0.14) : palette.page,
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selected ? palette.primary : .clear, lineWidth: 1.5))
            .opacity(unlocked ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityLabel(unlocked
            ? (selected ? String(localized: "\(name)、選択中") : name)
            : String(localized: "\(name)。あと\(requiredDays - recordedDays)日の記録で選べます"))
    }

    // MARK: - 見え方

    private var appearanceSection: some View {
        VStack(spacing: 12) {
            Toggle("薄明かり", isOn: $dim)
        }
        .padding(16)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "見え方"))
    }

    // MARK: - 気圧との関係（設計書 v1.0 の相関レポート、記述のみ）

    private var correlationSection: some View {
        let report = PressureCorrelationReport.make(
            observations: records.filter(\.hasFactors).map { record in
                SymptomObservation(factors: record.factors,
                                   wasBad: record.feeling == HealthFeelingBadRaw)
            },
            recordedDays: analysableDays)
        return VStack(alignment: .leading, spacing: 8) {
            Text("気圧との関係").font(.subheadline.weight(.semibold)).foregroundStyle(palette.muted)
            switch report {
            case .insufficient(let remaining):
                Text("あと\(remaining)日分の記録で、気圧との関係を見られます。")
                    .foregroundStyle(palette.muted)
            case .ready(let summary):
                Text(Self.describe(summary))
            }
        }
        .font(.subheadline)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 20))
    }

    /// 記述に留める（§6.3）。「気圧に弱い」等の評価語や申告への言及は付けない。
    static func describe(_ summary: PressureCorrelationReport.Summary) -> String {
        func line(_ label: String, count: Int, bad: Int, rate: Double?) -> String {
            guard let rate else { return String(localized: "\(label)の記録はまだありません。") }
            let percent = Int((rate * 100).rounded())
            return String(localized: "\(label)の記録 \(count) 件のうち、つらいが \(bad) 件（\(percent)%）。")
        }
        return line(String(localized: "気圧が動いていたとき"), count: summary.activeCount, bad: summary.activeBad,
                    rate: summary.activeRate)
            + "\n" + line(String(localized: "気圧が穏やかだったとき"), count: summary.calmCount, bad: summary.calmBad,
                         rate: summary.calmRate)
    }

    // MARK: - 記録ログ

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("これまでの記録").font(.subheadline.weight(.semibold)).foregroundStyle(palette.muted)
            if records.isEmpty {
                Text("まだ記録がありません。ホームの「げんき」「ふつう」「つらい」から記録できます。")
                    .foregroundStyle(palette.muted)
            } else {
                Text("記録 \(recordedDays) 日")
                    .font(.footnote.monospacedDigit()).foregroundStyle(palette.muted)
                VStack(spacing: 0) {
                    ForEach(records.prefix(60)) { record in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(record.date.formatted(.dateTime.month().day().weekday()
                                    .hour().minute()))
                                    .monospacedDigit()
                                Spacer()
                                Text(HealthFeeling(rawValue: record.feeling)?.label ?? record.feeling)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(record.feeling == HealthFeelingBadRaw
                                                     ? palette.ink : palette.muted)
                            }
                            if let weather = RecordWeatherText.summary(for: record) {
                                Text(weather)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(palette.muted)
                            }
                        }
                        .font(.subheadline)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 20))
    }
}

/// `HealthFeeling.bad.rawValue`。CheckInRecord は rawValue 文字列で保存している。
private let HealthFeelingBadRaw = HealthFeeling.bad.rawValue
