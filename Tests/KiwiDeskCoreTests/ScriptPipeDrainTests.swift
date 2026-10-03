import Foundation
import Testing

@Suite("Script fixture pipe draining")
struct ScriptPipeDrainTests {
    @Test(
        "both stream orders drain beyond pipe capacity",
        arguments: [
            false, true,
        ]
    )
    func bothStreams(stderrFirst: Bool) throws {
        let run = try Self.run(stderrFirst: stderrFirst)
        #expect(run.status == 0)
        #expect(run.stdout == String(repeating: "o", count: 100_000))
        #expect(run.stderr == String(repeating: "e", count: 100_000))
    }

    @Test("parallel script callers cannot starve their pipe readers")
    func concurrentCallers() async throws {
        let count = try await withThrowingTaskGroup(of: Bool.self) { group in
            for index in 0..<16 {
                group.addTask {
                    let run = try Self.run(
                        stderrFirst: index.isMultiple(of: 2)
                    )
                    return run.status == 0
                        && run.stdout == String(repeating: "o", count: 100_000)
                        && run.stderr == String(repeating: "e", count: 100_000)
                }
            }
            var count = 0
            for try await matches in group {
                #expect(matches)
                count += 1
            }
            return count
        }
        #expect(count == 16)
    }

    private static func run(stderrFirst: Bool) throws -> ScriptRun {
        let writes = [
            "sys.stdout.write('o' * 100_000)",
            "sys.stderr.write('e' * 100_000)",
        ]
        let ordered = stderrFirst ? Array(writes.reversed()) : writes
        let script = "import sys\n" + ordered.joined(separator: "\n")
        return try spawn("/usr/bin/python3", ["-c", script])
    }

}
