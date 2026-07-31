import Foundation
import Testing
@testable import Kakuro

@Suite struct GenerationPerformanceTests {

    /// p90 wall-clock budgets per size, in seconds, on the DEBUG simulator
    /// build (-Onone is ~5x slower than the shipping -O binary; native release
    /// measures ~0.03s/0.3s/2s). Generation runs on a background task with a
    /// pre-warmed cache in the app, so these bound runaway search, not UX.
    private static let budgets: [BoardSize: TimeInterval] = [
        .small: 3.0,
        .medium: 12.0,
        .large: 30.0,
    ]

    @Test(arguments: BoardSize.allCases)
    func generationMeetsBudget(size: BoardSize) async {
        // Run off the main actor, as the app does.
        let times: [TimeInterval] = await Task.detached {
            var results: [TimeInterval] = []
            for seed: UInt64 in 1...10 {
                let start = Date()
                _ = KakuroGenerator.generate(.init(size: size, difficulty: .medium, seed: seed))
                results.append(Date().timeIntervalSince(start))
            }
            return results
        }.value
        let p90 = times.sorted()[Int(Double(times.count) * 0.9) - 1]
        #expect(p90 <= Self.budgets[size]!,
                "\(size) p90 \(p90)s over budget \(Self.budgets[size]!)s; times: \(times)")
    }
}
