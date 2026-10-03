import Darwin
import Foundation
import Testing

@Suite("Packaged app signing modes")
struct BuildSigningModeTests {
    @Test(
        "every signed piece uses its identity's runtime policy",
        arguments: ["-", "Developer ID Application: Test"]
    )
    func runtimePolicy(identity: String) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("signing-mode-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let framework = root.appendingPathComponent("Sparkle.framework")
        let version = framework.appendingPathComponent("Versions/Current")
        let pieces = [
            "XPCServices/Downloader.xpc", "XPCServices/Installer.xpc",
            "Autoupdate", "Updater.app",
        ]
        for piece in pieces {
            try FileManager.default.createDirectory(
                at: version.appendingPathComponent(piece),
                withIntermediateDirectories: true
            )
        }
        let resources = root.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(
            at: resources.appendingPathComponent("Test.bundle"),
            withIntermediateDirectories: true
        )
        let block = try signingBlock()
        let command = """
            set -euo pipefail
            IDENTITY="$1"; FRAMEWORKS="$2"; RES="$2/Resources"
            APP="$2/KiwiDesk.app"
            codesign() {
                printf 'call'
                printf '\\t%s' "$@"
                printf '\\n'
            }
            \(block)
            """
        let run = try spawn(
            "/bin/bash",
            ["-c", command, "_", identity, root.path]
        )
        try #require(run.status == 0, "stderr: \(run.stderr)")
        let calls = run.stdout.split(separator: "\n").filter {
            $0.hasPrefix("call\t")
        }.map { $0.split(separator: "\t").dropFirst().map(String.init) }
        let signed = calls.filter { $0.contains("--sign") }
        #expect(signed.count == 7)
        let physical = try #require(realpath(version.path, nil))
        defer { free(physical) }
        let physicalVersion = String(cString: physical)
        let targets =
            pieces.map {
                physicalVersion + "/" + $0
            }
            + [
                framework.path,
                resources.appendingPathComponent(
                    "Test.bundle"
                ).path, root.appendingPathComponent("KiwiDesk.app").path,
            ]
        #expect(signed.compactMap { $0.last } == targets)
        for arguments in signed {
            #expect(arguments.contains(identity))
            #expect(arguments.contains("--force"))
            let options = try #require(arguments.firstIndex(of: "--options"))
            try #require(arguments.indices.contains(options + 1))
            if identity == "-" {
                #expect(arguments[options + 1] == "0")
                #expect(arguments.contains("--timestamp=none"))
            } else {
                #expect(arguments[options + 1] == "runtime")
                #expect(arguments.contains("--timestamp"))
            }
        }
        #expect(
            calls.last == [
                "--verify", "--deep", "--strict",
                root.appendingPathComponent("KiwiDesk.app").path,
            ]
        )
    }

    private func signingBlock() throws -> String {
        let text = try buildAppScriptWithoutComments()
        let start = try #require(text.range(of: #"TS=(--timestamp)"#))
        let end = try #require(
            text.range(of: #"codesign --verify --deep --strict "$APP""#)
        )
        return String(text[start.lowerBound..<end.upperBound])
    }
}
