import CoreLocation
import os

/// Passive location tracker using significant location changes.
/// Triggers on ~500m cell tower changes — minimal battery, works in background,
/// no persistent blue location indicator. Posts to /webhook/nexus-location.
final class LocationTrackingService: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let shared = LocationTrackingService()

    private let manager = CLLocationManager()
    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "location")
    private let minDistanceFilter: CLLocationDistance = 200
    private let minTimeBetweenUpdates: TimeInterval = 120 // 2 min debounce

    private var lastSentLocation: CLLocation?
    private var lastSentTime: Date?
    private var isMonitoring = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
    }

    // MARK: - Public

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    func requestPermission() {
        logger.info("Requesting always authorization")
        manager.requestAlwaysAuthorization()
    }

    func startTracking() {
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else {
            logger.warning("Significant location change monitoring not available")
            return
        }

        let status = manager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            logger.warning("Location not authorized: \(String(describing: status))")
            requestPermission()
            return
        }

        guard !isMonitoring else { return }
        isMonitoring = true
        manager.startMonitoringSignificantLocationChanges()
        logger.info("Started significant location change monitoring")
    }

    func stopTracking() {
        guard isMonitoring else { return }
        isMonitoring = false
        manager.stopMonitoringSignificantLocationChanges()
        logger.info("Stopped location tracking")
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Debounce: skip if too recent or too close
        if let lastTime = lastSentTime,
           Date().timeIntervalSince(lastTime) < minTimeBetweenUpdates {
            logger.debug("Skipping location update: too soon (\(Date().timeIntervalSince(lastTime))s)")
            return
        }

        if let lastLoc = lastSentLocation,
           location.distance(from: lastLoc) < minDistanceFilter {
            logger.debug("Skipping location update: too close (\(location.distance(from: lastLoc))m)")
            return
        }

        // Filter out stale or inaccurate locations
        let age = abs(location.timestamp.timeIntervalSinceNow)
        guard age < 300, location.horizontalAccuracy >= 0, location.horizontalAccuracy < 1000 else {
            logger.debug("Skipping stale/inaccurate location: age=\(age)s accuracy=\(location.horizontalAccuracy)m")
            return
        }

        lastSentLocation = location
        lastSentTime = Date()

        logger.info("Significant location change: \(location.coordinate.latitude), \(location.coordinate.longitude) (±\(location.horizontalAccuracy)m)")

        Task { await sendLocation(location) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.error("Location error: \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        logger.info("Authorization changed: \(String(describing: status))")

        if status == .authorizedAlways || status == .authorizedWhenInUse {
            if AppSettings.shared.locationTrackingEnabled {
                startTracking()
            }
        } else if status == .denied || status == .restricted {
            stopTracking()
        }
    }

    // MARK: - API

    private func sendLocation(_ location: CLLocation) async {
        guard let apiKey = KeychainManager.shared.apiKey else {
            logger.warning("No API key, skipping location send")
            return
        }

        let baseURL = NetworkConfig.shared.baseURL
        guard let url = URL(string: "\(baseURL)/webhook/nexus-location") else {
            logger.error("Invalid location webhook URL")
            return
        }

        let payload: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "event_type": "poll",
            "source": "iphone",
            "activity": "significant_change",
            "location_name": NSNull()
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            logger.error("Failed to serialize location payload")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    logger.debug("Location sent successfully")
                } else {
                    let responseBody = String(data: data, encoding: .utf8) ?? "no body"
                    logger.warning("Location webhook returned \(httpResponse.statusCode): \(responseBody)")
                }
            }
        } catch {
            logger.error("Failed to send location: \(error.localizedDescription)")
        }
    }
}
