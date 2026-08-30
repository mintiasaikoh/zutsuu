import Testing
import Foundation
@testable import RiskEngine

@Test("リスクレベルは大小比較できる")
func riskLevelIsComparable() {
    #expect(RiskLevel.calm < RiskLevel.danger)
    #expect(RiskLevel.allCases.count == 4)
}

@Test("リスク要因の合計は各要素の和")
func riskFactorsTotal() {
    let f = RiskFactors(pressure: 3, humidity: 2, precipitation: 1, temperature: 2)
    #expect(f.total == 8)
}
