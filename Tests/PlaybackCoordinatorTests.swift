import XCTest
@testable import Spotlightify

@MainActor
final class PlaybackCoordinatorTests: XCTestCase {
    func testPreferredDevicePicksActiveComputerFirst() throws {
        let devices = [
            SpotifyDevice(id: "phone", isActive: true, isRestricted: false, name: "iPhone", type: "Smartphone"),
            SpotifyDevice(id: "mac", isActive: true, isRestricted: false, name: "Work Mac", type: "Computer")
        ]

        let device = PlaybackCoordinator.preferredDevice(from: devices)

        XCTAssertEqual(device?.id, "mac")
    }

    func testPreferredDeviceFallsBackToAnyComputer() throws {
        let devices = [
            SpotifyDevice(id: "tablet", isActive: false, isRestricted: false, name: "iPad", type: "Tablet"),
            SpotifyDevice(id: "mac", isActive: false, isRestricted: false, name: "MacBook Pro", type: "Computer")
        ]

        let device = PlaybackCoordinator.preferredDevice(from: devices)

        XCTAssertEqual(device?.id, "mac")
    }

    func testResolvePlaybackDeviceRejectsRestrictedDevices() async throws {
        let configuration = AppConfiguration(bundledSpotifyClientID: "test", callbackScheme: "spotlightify")
        let keychain = KeychainStore(service: "mock")
        let authManager = SpotifyAuthManager(
            configuration: configuration,
            keychain: keychain,
            clientIDProvider: { "test" },
            session: .shared
        )
        let client = SpotifyAPIClient(authManager: authManager)
        let coordinator = PlaybackCoordinator(apiClient: client)
        let devices = [
            SpotifyDevice(id: "mac", isActive: true, isRestricted: true, name: "MacBook Pro", type: "Computer")
        ]

        do {
            _ = try await coordinator.resolvePlaybackDevice(from: devices)
            XCTFail("Expected restricted device error")
        } catch let error as SpotifyAPIError {
            XCTAssertEqual(error, .restrictedDevice)
        }
    }

    func testResolvePlaybackDeviceUsesCurrentComputerWhenDevicesListIsEmpty() async throws {
        let configuration = AppConfiguration(bundledSpotifyClientID: "test", callbackScheme: "spotlightify")
        let keychain = KeychainStore(service: "mock")
        let authManager = SpotifyAuthManager(
            configuration: configuration,
            keychain: keychain,
            clientIDProvider: { "test" },
            session: .shared
        )
        let client = SpotifyAPIClient(authManager: authManager)
        let coordinator = PlaybackCoordinator(apiClient: client)
        let currentDevice = SpotifyDevice(
            id: "current-mac",
            isActive: true,
            isRestricted: false,
            name: "MacBook Pro",
            type: "Computer"
        )

        let device = try await coordinator.resolvePlaybackDevice(
            from: [],
            currentPlaybackDevice: currentDevice
        )

        XCTAssertEqual(device.id, "current-mac")
        XCTAssertTrue(device.isActive)
    }
}
