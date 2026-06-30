import XCTest
@testable import FallbackWiFi

final class FallbackPasswordStoreTests: XCTestCase {
    private var storeDirectory: URL!
    private var recoveryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FallbackWiFiTests-\(UUID().uuidString)", isDirectory: true)
        recoveryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FallbackWiFiRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        FallbackPasswordStore.directoryOverride = storeDirectory
        FallbackPasswordStore.recoveryDirectoryOverride = recoveryDirectory
    }

    override func tearDownWithError() throws {
        FallbackPasswordStore.directoryOverride = nil
        FallbackPasswordStore.recoveryDirectoryOverride = nil
        if let storeDirectory, FileManager.default.fileExists(atPath: storeDirectory.path) {
            try FileManager.default.removeItem(at: storeDirectory)
        }
        if let recoveryDirectory, FileManager.default.fileExists(atPath: recoveryDirectory.path) {
            try FileManager.default.removeItem(at: recoveryDirectory)
        }
        try super.tearDownWithError()
    }

    func testPasswordPersistsInLocalPrivateFile() throws {
        try FallbackPasswordStore.save("secret-password", for: "JP iPhone")

        XCTAssertTrue(FallbackPasswordStore.hasPassword(for: "JP iPhone"))
        XCTAssertEqual(try FallbackPasswordStore.password(for: "JP iPhone"), "secret-password")

        let fileURL = storeDirectory.appendingPathComponent("backup-passwords.json")
        let recoveryFileURL = recoveryDirectory.appendingPathComponent("backup-passwords.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recoveryFileURL.path))
        XCTAssertEqual(try posixPermissions(at: storeDirectory), 0o700)
        XCTAssertEqual(try posixPermissions(at: fileURL), 0o600)
        XCTAssertEqual(try posixPermissions(at: recoveryDirectory), 0o700)
        XCTAssertEqual(try posixPermissions(at: recoveryFileURL), 0o600)
    }

    func testPasswordCanBeRemovedFromLocalFile() throws {
        try FallbackPasswordStore.save("secret-password", for: "JP iPhone")

        FallbackPasswordStore.deletePassword(for: "JP iPhone")

        XCTAssertFalse(FallbackPasswordStore.hasPassword(for: "JP iPhone"))
        XCTAssertNil(try FallbackPasswordStore.password(for: "JP iPhone"))
    }

    func testPasswordIsRestoredWhenPrimaryFileIsMissing() throws {
        try FallbackPasswordStore.save("secret-password", for: "JP iPhone")
        try FileManager.default.removeItem(at: storeDirectory)

        XCTAssertTrue(FallbackPasswordStore.hasPassword(for: "JP iPhone"))
        XCTAssertEqual(try FallbackPasswordStore.password(for: "JP iPhone"), "secret-password")

        let restoredFileURL = storeDirectory.appendingPathComponent("backup-passwords.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: restoredFileURL.path))
    }

    func testRecoveryFileIsBackfilledWhenExistingPrimaryIsRead() throws {
        try FallbackPasswordStore.save("secret-password", for: "JP iPhone")
        try FileManager.default.removeItem(at: recoveryDirectory)

        XCTAssertEqual(try FallbackPasswordStore.password(for: "JP iPhone"), "secret-password")

        let recoveryFileURL = recoveryDirectory.appendingPathComponent("backup-passwords.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recoveryFileURL.path))
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.posixPermissions] as? Int ?? 0
    }
}
