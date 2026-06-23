import XCTest
@testable import FallbackWiFi

final class WiFiParsingTests: XCTestCase {
    func testWiFiInterfaceParsesHardwarePortsOutput() {
        let output = """
        Hardware Port: Ethernet Adapter (en4)
        Device: en4

        Hardware Port: Wi-Fi
        Device: en0
        Ethernet Address: 60:3e:5f:49:2e:9e
        """

        XCTAssertEqual(WiFiParsing.wifiInterface(from: output), "en0")
    }

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
