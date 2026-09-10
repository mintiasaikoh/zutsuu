// /Users/mymac/zutsuu/ios/ZutsuuApp/Sources/KiabouTabView.swift
// きあぼうタブ。着せ替え・見え方の設定・記録ログの確認を行う。
// 記録の入口はホームに一本化し、このタブは相棒と過ごす場所にするため（Plan 3 Task 7）。
// 関連: ../../ZutsuuKit/Sources/KiabouUI/KiabouOutfit.swift, TodayView.swift, CheckInStore.swift
import SwiftUI
import SwiftData
import KiabouUI

struct KiabouTabView: View {
    @Environment(ForecastPipeline.self) private var pipeline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("kiabou.native.cove") private var cove = true
    @AppStorage("kiabou.native.dim") private var dim = false
    @AppStorage("kiabou.outfit") private var outfitID = KiabouOutfit.original.id
    @Query(sort: \CheckInRecord.date, order: .reverse) private var records: [CheckInRecord]

    private var palette: KiabouPalette { KiabouPalette(dim: dim) }
    /// 解放判定は @Query から直接数える。パイプラインの予報更新を待つと、
    /// 予報が取れるまで全部ロックに見えてしまう。
    private var recordedDays: Int {
        Set(records.map { Calendar.current.startOfDay(for: $0.date) }).count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    KiabouStage(resting: false, cove: cove, dim: dim,
                                moving: !reduceMotion && scenePhase == .active,
                                outfit: .outfit(id: outfitID))
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    outfitSection
                    appearanceSection
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

    @ViewBuilder
    private func outfitCell(_ outfit: KiabouOutfit) -> some View {
        let unlocked = outfit.isUnlocked(recordedDays: recordedDays)
        let selected = outfit.id == outfitID
        Button {
            if unlocked { outfitID = outfit.id }
        } label: {
            VStack(spacing: 4) {
                Text(outfit.name).font(.subheadline.weight(selected ? .bold : .regular))
                if !unlocked {
                    Text("あと\(outfit.requiredDays - recordedDays)日")
                        .font(.caption.monospacedDigit()).foregroundStyle(palette.muted)
                } else if selected {
                    Text("いまの姿").font(.caption).foregroundStyle(palette.muted)
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
            ? "\(outfit.name)\(selected ? "、選択中" : "")"
            : "\(outfit.name)。あと\(outfit.requiredDays - recordedDays)日の記録で選べます")
    }

    // MARK: - 見え方

    private var appearanceSection: some View {
        VStack(spacing: 12) {
            Toggle("入り江の背景", isOn: $cove)
            Toggle("薄明かり", isOn: $dim)
        }
        .padding(16)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("見え方")
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
