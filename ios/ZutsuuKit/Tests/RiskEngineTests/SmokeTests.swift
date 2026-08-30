import Testing
@testable import RiskEngine

@Test("パッケージがビルドできる")
func packageBuilds() {
    #expect(RiskEngine.version == "0.1.0")
}
