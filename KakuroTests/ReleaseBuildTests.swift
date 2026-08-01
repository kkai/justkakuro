import Foundation
import Testing
@testable import Kakuro

/// Guards against shipping something that only makes sense while developing.
@Suite struct ReleaseBuildTests {

    /// The screenshot unlock grants the paid tier from a launch argument. It is
    /// wrapped in `#if DEBUG` so it cannot exist in the binary that ships;
    /// this fails the moment someone lifts it out of that block.
    ///
    /// Verified independently by building Release and checking the flag string
    /// is absent from the binary — this test is the cheap early warning.
    @Test func screenshotUnlockIsDebugOnly() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appending(path: "Kakuro/App/KakuroApp.swift"),
                                encoding: .utf8)
        guard let use = source.range(of: "screenshotUnlockFlag)") else {
            Issue.record("the screenshot unlock flag is no longer read; delete this test")
            return
        }
        let before = source[source.startIndex..<use.lowerBound]
        let lastDebug = before.range(of: "#if DEBUG", options: .backwards)
        let lastEndif = before.range(of: "#endif", options: .backwards)
        #expect(lastDebug != nil, "the screenshot unlock is not inside #if DEBUG")
        if let lastDebug, let lastEndif {
            #expect(lastDebug.lowerBound > lastEndif.lowerBound,
                    "the screenshot unlock sits outside its #if DEBUG block")
        }
    }

    /// The privacy manifest must use Apple's key names exactly.
    ///
    /// Builds 2 and 3 were rejected with ITMS-91056 because the manifest said
    /// `NSPrivacyAccessedAPIReasons` instead of `NSPrivacyAccessedAPITypeReasons`.
    /// Nothing local catches that: the file is valid property list, so
    /// `plutil -lint` passes, `altool --validate-app` passes, and the build
    /// processes to VALID. Apple's own validator runs afterwards and reports by
    /// email only.
    ///
    /// The key sets below are written out by hand from Apple's documentation.
    /// That is the whole point. The check that missed this the first time built
    /// its allowlist by reading the manifest, so the misspelling was compared
    /// against itself and passed.
    @Test func privacyManifestUsesApplesKeyNames() throws {
        let topLevel: Set<String> = [
            "NSPrivacyTracking",
            "NSPrivacyTrackingDomains",
            "NSPrivacyCollectedDataTypes",
            "NSPrivacyAccessedAPITypes",
        ]
        let accessedAPI: Set<String> = [
            "NSPrivacyAccessedAPIType",
            "NSPrivacyAccessedAPITypeReasons",
        ]

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appending(path: "Kakuro/PrivacyInfo.xcprivacy"))
        guard let manifest = try PropertyListSerialization
            .propertyList(from: data, format: nil) as? [String: Any] else {
            Issue.record("the privacy manifest is not a dictionary")
            return
        }

        for key in manifest.keys {
            #expect(topLevel.contains(key), "\(key) is not a privacy manifest key")
        }

        let entries = manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        #expect(!entries.isEmpty, "the app uses UserDefaults, so it must declare a reason")
        for entry in entries {
            for key in entry.keys {
                #expect(accessedAPI.contains(key), "\(key) is not an accessed-API key")
            }
            for required in accessedAPI {
                #expect(entry[required] != nil, "the entry is missing \(required)")
            }
            let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
            #expect(!reasons.isEmpty, "a declared API needs at least one reason code")
        }
    }

    /// A release build should not carry developer logging.
    @Test func noPrintOrNSLogInShippedSources() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Kakuro")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty, "found no sources to scan")
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), !code.hasPrefix("///") else { continue }
                for banned in ["print(", "NSLog(", "debugPrint("] {
                    #expect(!code.contains(banned),
                            "\(file.lastPathComponent):\(index + 1) uses \(banned)")
                }
            }
        }
    }
}
