import CoreLocation
import os

/// Location tracker using CLCircularRegion geofencing + significant location changes.
/// Geofences fire reliably on boundary crossings via the motion coprocessor.
/// Significant changes (~500m cell tower) provide supplementary poll updates.
/// Posts to /webhook/nexus-location.
final class LocationTrackingService: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let shared = LocationTrackingService()

    private let manager = CLLocationManager()
    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "location")
    private let minTimeBetweenUpdates: TimeInterval = 120

    private var lastSentLocation: CLLocation?
    private var lastSentTime: Date?
    private var isMonitoring = false
    private var registeredRegions: [String: KnownZone] = [:]

    struct KnownZone {
        let id: Int
        let name: String
        let category: String
        let lat: Double
        let lng: Double
        let radiusMeters: Double
    }

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
        let status = manager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            logger.warning("Location not authorized: \(String(describing: status))")
            requestPermission()
            return
        }

        guard !isMonitoring else { return }
        isMonitoring = true

        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
            logger.info("Started significant location change monitoring")
        }

        Task { await fetchAndRegisterGeofences() }
    }

    func stopTracking() {
        guard isMonitoring else { return }
        isMonitoring = false
        manager.stopMonitoringSignificantLocationChanges()

        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
        registeredRegions.removeAll()
        logger.info("Stopped all location tracking")
    }

    // MARK: - Geofence Registration

    private func fetchAndRegisterGeofences() async {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            logger.warning("Region monitoring not available on this device")
            return
        }

        let zones = await fetchKnownZones()
        guard !zones.isEmpty else {
            logger.info("No known zones to register")
            return
        }

        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
        registeredRegions.removeAll()

        for zone in zones {
            let center = CLLocationCoordinate2D(latitude: zone.lat, longitude: zone.lng)
            let radius = min(zone.radiusMeters, manager.maximumRegionMonitoringDistance)
            let region = CLCircularRegion(center: center, radius: radius, identifier: "zone_\(zone.id)_\(zone.name)")
            region.notifyOnEntry = true
            region.notifyOnExit = true

            manager.startMonitoring(for: region)
            registeredRegions[region.identifier] = zone
            logger.info("Registered geofence: \(zone.name) (\(zone.category)) r=\(Int(radius))m")
        }

        logger.info("Registered \(zones.count) geofence(s)")
    }

    private func fetchKnownZones() async -> [KnownZone] {
        guard let apiKey = KeychainManager.shared.apiKey else {
            logger.warning("No API key, using hardcoded zones")
            return fallbackZones()
        }

        let baseURL = NetworkConfig.shared.baseURL
        guard let url = URL(string: "\(baseURL)/webhook/nexus-known-locations") else {
            logger.error("Invalid known-locations URL")
            return fallbackZones()
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                logger.warning("Known locations endpoint returned non-200, using fallback")
                return fallbackZones()
            }

            struct LocationsResponse: Decodable {
                let success: Bool
                let locations: [LocationEntry]
            }
            struct LocationEntry: Decodable {
                let id: Int
                let name: String
                let category: String
                let lat: Double
                let lng: Double
                let radius_meters: Int
            }

            let decoded = try JSONDecoder().decode(LocationsResponse.self, from: data)
            guard decoded.success else {
                logger.warning("Known locations response not successful, using fallback")
                return fallbackZones()
            }

            return decoded.locations.map { loc in
                KnownZone(id: loc.id, name: loc.name, category: loc.category,
                          lat: loc.lat, lng: loc.lng, radiusMeters: Double(loc.radius_meters))
            }
        } catch {
            logger.error("Failed to fetch known locations: \(error.localizedDescription)")
            return fallbackZones()
        }
    }

    private func fallbackZones() -> [KnownZone] {
        [
            KnownZone(id: 1, name: "gym", category: "gym",
                      lat: 25.07822362022749, lng: 55.14869064417944, radiusMeters: 150),
            KnownZone(id: 2, name: "work", category: "work",
                      lat: 25.07492398636361, lng: 55.14538845149844, radiusMeters: 150),
        ]
    }

    // MARK: - CLLocationManagerDelegate — Regions

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let zone = registeredRegions[region.identifier] else { return }
        logger.info("Entered geofence: \(zone.name) (\(zone.category))")

        Task {
            await sendGeofenceEvent(zone: zone, eventType: "enter")
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let zone = registeredRegions[region.identifier] else { return }
        logger.info("Exited geofence: \(zone.name) (\(zone.category))")

        Task {
            await sendGeofenceEvent(zone: zone, eventType: "exit")
        }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        let name = region?.identifier ?? "unknown"
        logger.error("Monitoring failed for \(name): \(error.localizedDescription)")
    }

    // MARK: - CLLocationManagerDelegate — Significant Changes

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        if let lastTime = lastSentTime,
           Date().timeIntervalSince(lastTime) < minTimeBetweenUpdates {
            return
        }

        let age = abs(location.timestamp.timeIntervalSinceNow)
        guard age < 300, location.horizontalAccuracy >= 0, location.horizontalAccuracy < 1000 else {
            logger.debug("Skipping stale/inaccurate location: age=\(age)s accuracy=\(location.horizontalAccuracy)m")
            return
        }

        lastSentLocation = location
        lastSentTime = Date()

        logger.info("Significant location change: \(location.coordinate.latitude), \(location.coordinate.longitude) (±\(location.horizontalAccuracy)m)")

        Task { await sendLocation(location, activity: "significant_change") }
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

    private func sendGeofenceEvent(zone: KnownZone, eventType: String) async {
        let payload: [String: Any] = [
            "latitude": zone.lat,
            "longitude": zone.lng,
            "event_type": eventType,
            "source": "iphone",
            "activity": "geofence",
            "location_name": zone.name
        ]
        await sendPayload(payload)
    }

    private func sendLocation(_ location: CLLocation, activity: String) async {
        let payload: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "event_type": "poll",
            "source": "iphone",
            "activity": activity,
            "location_name": NSNull()
        ]
        await sendPayload(payload)
    }

    private func sendPayload(_ payload: [String: Any]) async {
        guard let apiKey = KeychainManager.shared.apiKey else {
            logger.warning("No API key, skipping location send")
            return
        }

        let baseURL = NetworkConfig.shared.baseURL
        guard let url = URL(string: "\(baseURL)/webhook/nexus-location") else {
            logger.error("Invalid location webhook URL")
            return
        }

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
                    let eventType = payload["event_type"] as? String ?? "unknown"
                    let activity = payload["activity"] as? String ?? "unknown"
                    logger.debug("Location sent: \(eventType)/\(activity)")
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
