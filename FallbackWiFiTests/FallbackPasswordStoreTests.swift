import XCTest
@testable import FallbackWiFi

final class FallbackPasswordStoreTests: XCTestCase {
    private var storeDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FallbackWiFiTests-\(UUID().uuidString)", isDirectory: true)
        FallbackPasswordStore.directoryOverride = storeDirectory
    }

    override func tearDownWithError() throws {
        FallbackPasswordStore.directoryOverride = nil
        if let storeDirectory, FileManager.default.fileExists(atPath: storeDirectory.path) {
            try FileManager.default.removeItem(at: storeDirectory)
        }
        try super.tearDownWithError()
    }

    func testPasswordPersistsInLocalPrivateFile() throws {
        try FallbackPasswordStore.save("secret-password", for: "JP iPhone")

        XCTAssertTrue(FallbackPasswordStore.hasPassword(for: "JP iPhone"))
        XCTAssertEqual(try FallbackPasswordStore.password(for: "JP iPhone"), "secret-password")

        let fileURL = storeDirectory.appendingPathComponent("backup-passwords.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(try posixPermissions(at: storeDirectory), 0o700)
        XCTAssertEqual(try posixPermissions(at: fileURL), 0o600)
    }

    func testPasswordCanBeRemovedFromLocalFile() throws {
        try FallbackPasswordStore.save("secret-password", for: "JP iPhone")

        FallbackPasswordStore.deletePassword(for: "JP iPhone")

        XCTAssertFalse(FallbackPasswordStore.hasPassword(for: "JP iPhone"))
        XCTAssertNil(try FallbackPasswordStore.password(for: "JP iPhone"))
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.posixPermissions] as? Int ?? 0
    }
}
