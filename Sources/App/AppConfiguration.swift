import Foundation

struct AppConfiguration {
    let bundledSpotifyClientID: String
    let callbackScheme: String
    let oauthRedirectHost: String
    let oauthRedirectPort: UInt16
    let appSupportDirectory: URL
    let logsDirectory: URL
    let logFileURL: URL

    var redirectURI: String {
        "http://\(oauthRedirectHost):\(oauthRedirectPort)/callback"
    }

    init(
        bundledSpotifyClientID: String = "",
        callbackScheme: String = "spotlightify",
        oauthRedirectHost: String = "127.0.0.1",
        oauthRedirectPort: UInt16 = 43821,
        appSupportDirectory: URL = FileManager.default.temporaryDirectory,
        logsDirectory: URL = FileManager.default.temporaryDirectory,
        logFileURL: URL? = nil
    ) {
        self.bundledSpotifyClientID = bundledSpotifyClientID
        self.callbackScheme = callbackScheme
        self.oauthRedirectHost = oauthRedirectHost
        self.oauthRedirectPort = oauthRedirectPort
        self.appSupportDirectory = appSupportDirectory
        self.logsDirectory = logsDirectory
        self.logFileURL = logFileURL ?? logsDirectory.appendingPathComponent("app.log")
    }

    static func load(bundle: Bundle = .main, fileManager: FileManager = .default) -> AppConfiguration {
        let clientID = (bundle.object(forInfoDictionaryKey: "SpotifyClientID") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let callbackScheme = (bundle.object(forInfoDictionaryKey: "SpotifyCallbackScheme") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "spotlightify"
        let appName = (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Spotlightify"
        let appSupportDirectory = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ))?.appendingPathComponent(appName, isDirectory: true) ?? fileManager.temporaryDirectory.appendingPathComponent(appName, isDirectory: true)
        let logsRoot = (try? fileManager.url(
            for: .libraryDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ))?.appendingPathComponent("Logs", isDirectory: true) ?? fileManager.temporaryDirectory
        let logsDirectory = logsRoot.appendingPathComponent(appName, isDirectory: true)

        return AppConfiguration(
            bundledSpotifyClientID: clientID,
            callbackScheme: callbackScheme,
            oauthRedirectHost: "127.0.0.1",
            oauthRedirectPort: 43821,
            appSupportDirectory: appSupportDirectory,
            logsDirectory: logsDirectory
        )
    }
}
