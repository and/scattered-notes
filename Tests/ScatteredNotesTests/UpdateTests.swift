import XCTest
@testable import ScatteredNotes

final class UpdateTests: XCTestCase {
    private func v(_ text: String) -> AppVersion { AppVersion(text)! }

    func testVersionsCompareNumberByNumber() {
        XCTAssertLessThan(v("1.1.0"), v("1.1.1"))
        XCTAssertLessThan(v("v1.9.0"), v("1.10.0"))
        XCTAssertEqual(v("1.1"), v("1.1.0"))
        XCTAssertGreaterThan(v("2.0"), v("1.99.99"))
        XCTAssertNil(AppVersion("1.2.0-beta"))
        XCTAssertNil(AppVersion("latest"))
        XCTAssertNil(AppVersion(""))
    }

    private func release(tag: String, assets: [String] = ["ScatteredNotes-1.1.1-mac.zip", "ScatteredNotes-1.1.1-windows.exe"],
                         draft: Bool = false, prerelease: Bool = false, body: String = "Notes") throws -> Release {
        let json: [String: Any] = [
            "tag_name": tag, "name": "Scattered Notes \(tag)", "body": body,
            "html_url": "https://github.com/and/scattered-notes/releases/tag/\(tag)",
            "draft": draft, "prerelease": prerelease,
            "assets": assets.map { ["name": $0, "size": 10, "browser_download_url": "https://github.com/and/scattered-notes/releases/download/\(tag)/\($0)"] },
        ]
        return try JSONDecoder().decode(Release.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testOnlyNewerPublishedReleasesWithAMacDownloadAreOffered() throws {
        let installed = v("1.1.0")
        XCTAssertTrue(try release(tag: "v1.1.1").isUpdate(over: installed, skipped: nil))
        XCTAssertFalse(try release(tag: "v1.1.0").isUpdate(over: installed, skipped: nil))
        XCTAssertFalse(try release(tag: "v1.0.9").isUpdate(over: installed, skipped: nil))
        XCTAssertFalse(try release(tag: "v1.1.1", draft: true).isUpdate(over: installed, skipped: nil))
        XCTAssertFalse(try release(tag: "v1.1.1", prerelease: true).isUpdate(over: installed, skipped: nil))
        XCTAssertFalse(try release(tag: "v1.1.1", assets: ["ScatteredNotes-1.1.1-windows.exe"]).isUpdate(over: installed, skipped: nil))
        XCTAssertEqual(try release(tag: "v1.1.1").macAsset?.name, "ScatteredNotes-1.1.1-mac.zip")
    }

    func testSkippedVersionIsNotOfferedButALaterOneIs() throws {
        XCTAssertFalse(try release(tag: "v1.1.1").isUpdate(over: v("1.1.0"), skipped: "v1.1.1"))
        XCTAssertTrue(try release(tag: "v1.2.0").isUpdate(over: v("1.1.0"), skipped: "v1.1.1"))
    }

    func testNotesDropTheDownloadTable() throws {
        let notes = try release(tag: "v1.1.1", body: "Intro\r\n\r\n| Computer | Download |\r\n|---|---|\r\n| Mac | x |\r\n\r\n### Fixed\r\n- Sync").notes
        XCTAssertEqual(notes, "Intro\n\n\n### Fixed\n- Sync")
    }

    func testSignatureCheckRejectsAnUnsignedApp() throws {
        let fake = FileManager.default.temporaryDirectory.appendingPathComponent("Fake-\(UUID().uuidString).app/Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: fake, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: fake.deletingLastPathComponent().deletingLastPathComponent()) }
        try Data("#!/bin/sh\n".utf8).write(to: fake.appendingPathComponent("ScatteredNotes"))
        XCTAssertThrowsError(try UpdateChecker.verifySignature(of: fake.deletingLastPathComponent().deletingLastPathComponent()))
    }

    func testSignatureCheckAcceptsTheNotarizedRelease() throws {
        let release = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/release/export/ScatteredNotes.app")
        guard FileManager.default.fileExists(atPath: release.path) else { throw XCTSkip("No release build; run scripts/release.sh") }
        XCTAssertNoThrow(try UpdateChecker.verifySignature(of: release))
    }
}
