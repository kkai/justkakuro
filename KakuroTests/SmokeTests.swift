import Testing
@testable import Kakuro

@Suite struct SmokeTests {
    @Test func appTypesInstantiate() {
        _ = ContentView()
    }
}
