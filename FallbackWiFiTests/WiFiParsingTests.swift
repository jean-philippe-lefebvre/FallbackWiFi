import XCTest
@testable import FallbackWiFi

final class WiFiParsingTests: XCTestCase {
    func testPreferredNetworksDropsHeaderAndTrimsNames() {
        let output = """
        Preferred networks on en0:
            Home WiFi
            JP iPhone
            Office
        """

        XCTAssertEqual(
            WiFiParsing.preferredNetworks(from: output),
            ["Home WiFi", "JP iPhone", "Office"]
        )
    }

    func testCurrentNetworkParsesNetworksetupOutput() {
        let output = "Current Wi-Fi Network: JP iPhone\n"
        XCTAssertEqual(WiFiParsing.currentNetwork(from: output), "JP iPhone")
    }

    func testCurrentNetworkReturnsNilWhenDisconnected() {
        let output = "You are not associated with an AirPort network.\n"
        XCTAssertNil(WiFiParsing.currentNetwork(from: output))
    }
}
