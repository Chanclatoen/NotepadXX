import XCTest
@testable import NotepadXXCore

/// Test, benchmark and screenshot runs must not write into the user's defaults.
final class IsolatedDefaultsTests: XCTestCase {
    func testTestRunsUseAPrivateSuite() {
        XCTAssertTrue(AppDefaults.isIsolated)
        XCTAssertNotEqual(AppDefaults.store, UserDefaults.standard)
    }

    func testWritesStayOutOfTheStandardDomain() {
        let key = "NotepadXX.IsolationProbe.\(UUID().uuidString)"
        AppDefaults.store.set("x", forKey: key)
        defer { AppDefaults.store.removeObject(forKey: key) }
        XCTAssertEqual(AppDefaults.store.string(forKey: key), "x")
        XCTAssertNil(UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[key])
        XCTAssertNil(UserDefaults.standard.object(forKey: key))
    }
}
