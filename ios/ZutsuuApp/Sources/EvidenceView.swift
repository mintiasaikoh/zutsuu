// /Users/mymac/zutsuu/ios/ZutsuuApp/Sources/EvidenceView.swift
// 設定 → 「スコアの根拠」。配点の根拠にした文献を規則ごとに示す（設計書 §6.8）。
// 一覧の正典は docs/riskengine-api.md の参考文献節。ここはその写しで、他社アプリ名は出さない。
// 関連: SettingsView.swift, ../../../docs/riskengine-api.md §3
import SwiftUI

struct EvidenceView: View {
    var body: some View {
        List {
            Section {
                Text("これらの研究はこのアプリを検証したものではありません。気圧・湿度・雨・気温の配点を決めるときに参考にした、査読済みの文献です。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(EvidenceRule.all) { rule in
                Section(rule.title) {
                    Text(rule.basis)
                    ForEach(rule.references) { reference in
                        ReferenceRow(reference: reference)
                    }
                }
            }
        }
        .navigationTitle("スコアの根拠")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ReferenceRow: View {
    let reference: Reference

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reference.citation)
                .font(.footnote)
            Link("doi:\(reference.doi)", destination: reference.url)
                .font(.footnote)
        }
        .padding(.vertical, 2)
    }
}

struct EvidenceRule: Identifiable {
    let title: String
    let basis: String
    let references: [Reference]
    var id: String { title }

    static let all: [EvidenceRule] = [
        EvidenceRule(
            title: String(localized: "気圧の変化を、絶対値より重く見る"),
            basis: String(localized: "6 時間前からの気圧低下が頭痛の発生をもっとも強く説明し、気圧そのものの高低より変化のほうが効くことが、4 万人規模の記録で示されています。6 時間の窓を置いているのはこのためです。"),
            references: [.katsuki2023]),
        EvidenceRule(
            title: String(localized: "下がるときも、上がるときも見る"),
            basis: String(localized: "低気圧ではなく高気圧や気圧の上昇で不調になる人が実在し、集団の平均では効果が打ち消されることがあります。7 千人規模の発作記録でも、1 日で 20 hPa 以上上がった日に発作が増えていました。"),
            references: [.becker2011, .portt2026]),
        EvidenceRule(
            title: String(localized: "雨の配点は小さめ"),
            basis: String(localized: "雨は湿度や気圧と一緒に動くため、それだけの寄与は小さいと分かっています。4 万人規模の記録では気象要因のうち最下位、2 千人規模の慢性痛の記録では差がありませんでした。"),
            references: [.katsuki2023, .dixon2019]),
    ]
}

struct Reference: Identifiable {
    let citation: String
    let doi: String
    var id: String { doi }
    var url: URL { URL(string: "https://doi.org/\(doi)")! }

    static let katsuki2023 = Reference(
        citation: "Katsuki M, et al. Investigating the effects of weather on headache occurrence using a smartphone application and artificial intelligence. Headache. 2023;63(5):585–600.",
        doi: "10.1111/head.14482")
    static let becker2011 = Reference(
        citation: "Becker WJ. Weather and migraine: Can so many patients be wrong? Cephalalgia. 2011;31(4):387–390.",
        doi: "10.1177/0333102410385583")
    static let portt2026 = Reference(
        citation: "Portt AE, Gasparrini A, Ge E, et al. Weather, air pollution, and migraine: A case-time series analysis examining environmental exposures and transient health outcomes recorded via smartphone application. Environ Epidemiol. 2026;10(3):e475.",
        doi: "10.1097/ee9.0000000000000475")
    static let dixon2019 = Reference(
        citation: "Dixon WG, Beukenhorst AL, Yimer BB, et al. How the weather affects the pain of citizen scientists using a smartphone app. npj Digit Med. 2019;2:105.",
        doi: "10.1038/s41746-019-0180-3")
}
