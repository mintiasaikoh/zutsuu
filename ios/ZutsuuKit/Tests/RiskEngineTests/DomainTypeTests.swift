import Testing
import Foundation
import RiskEngine

@Suite("ドメイン型")
struct DomainTypeTests {
    @Test("リスクレベルは大小比較できる")
    func riskLevelIsComparable() {
        #expect(RiskLevel.calm < RiskLevel.danger)
        #expect(RiskLevel.allCases.count == 4)
    }

    @Test("リスクレベルの生値は 1〜4（TypeScript 実装との移植契約）")
    func riskLevelRawValues() {
        #expect(RiskLevel.allCases.map(\.rawValue) == [1, 2, 3, 4])
    }

    @Test("allCases は昇順に並んでいる")
    func riskLevelAllCasesAreAscending() {
        #expect(RiskLevel.allCases == RiskLevel.allCases.sorted())
    }

    @Test("リスク要因の合計は各要素の和")
    func riskFactorsTotal() {
        let f = RiskFactors(pressureChange: 2, pressureBaseline: 1,
                            humidity: 2, precipitation: 1, temperature: 2)
        #expect(f.total == 8)
    }

    @Test("気圧要因は変化量とその土地としての低さの和")
    func riskFactorsPressureIsSumOfItsParts() {
        let f = RiskFactors(pressureChange: 5, pressureBaseline: 3,
                            humidity: 0, precipitation: 0, temperature: 0)
        #expect(f.pressure == 8)
    }

    @Test("気圧変化量は時間窓ごとに保持される")
    func pressureChangesKeepsEachWindow() {
        let c = PressureChanges(oneHour: -1.5, threeHour: -4.0, sixHour: -6.5)
        #expect(c.oneHour == -1.5)
        #expect(c.threeHour == -4.0)
        #expect(c.sixHour == -6.5)
    }
}
