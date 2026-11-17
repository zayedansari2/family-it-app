import CoreWLAN
import CoreLocation

/// CoreWLAN's synchronous reads run off the UI actor. No scans, joins or credentials.
actor WiFiStatusService: WiFiStatusProviding {
    func currentStatus() async -> WiFiStatus {
        guard let interface = CWWiFiClient.shared().interface() else {
            return .init(state: .unavailable)
        }
        let authorized = await MainActor.run {
            let status = CLLocationManager().authorizationStatus
            return status == .authorizedAlways
        }
        // Only report disconnected when privacy access is granted and no PHY link is active.
        let disconnected = authorized && interface.activePHYMode() == CWPHYMode.modeNone
        return WiFiStatus.map(hasInterface: true, powered: interface.powerOn(),
                              associated: disconnected ? false : nil, ssid: interface.ssid())
    }
}

/// Location is optional, requested only through the explicit connection-check button.
@MainActor final class WiFiLocationPermission: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    override init() { super.init(); manager.delegate = self }
    func request() { manager.requestWhenInUseAuthorization() }
}
