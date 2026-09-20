import SwiftUI
import Foundation
import Combine
#if canImport(MapKit)
import MapKit
#endif
#if canImport(CoreLocation)
import CoreLocation
#endif

final class CinemaSearchService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var userCoordinate: CLLocationCoordinate2D?
    @Published var countryCode: String?
    @Published var theaters: [CinemaTheater] = []
    @Published var isSearching: Bool = false
    @Published var lastError: String?
    /// True once AMC has confirmed at least one showtime for this film — used to
    /// hide the section entirely for films that are no longer in cinemas.
    @Published var amcEverHadResults: Bool = false
    /// True once the AMC search has completed (regardless of result count).
    /// Distinguishes "search ran and found nothing nearby" from "search hasn't run yet".
    @Published var amcSearchCompleted: Bool = false
    /// When the cached AMC data was originally fetched from the AMC API (nil until first search completes).
    @Published var dataLastUpdated: Date?

    private let manager = CLLocationManager()
    private var pendingContinuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermissionIfNeeded() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func loadNearbyTheaters(filmTitle: String, forceRequestPermission: Bool = true) async {
        if forceRequestPermission {
            requestPermissionIfNeeded()
        }

        guard let location = await fetchOneShotLocation() else {
            lastError = "Location unavailable."
            return
        }

        let coord = location.coordinate
        userCoordinate = coord
        await resolveCountry(for: location)

        isSearching = true
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "movie theater"
        if #available(iOS 18.0, *) {
            request.resultTypes = .pointOfInterest
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.movieTheater])
        } else {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.movieTheater])
        }
        request.region = MKCoordinateRegion(
            center: coord,
            latitudinalMeters: 60_000,
            longitudinalMeters: 60_000
        )

        do {
            let response = try await MKLocalSearch(request: request).start()
            theaters = response.mapItems.compactMap { item in
                let name = item.name ?? "Cinema"
                let coordinate = CinemaMapKitBridge.coordinate(of: item)
                let identifier = "\(name)|\(coordinate.latitude)|\(coordinate.longitude)"
                let chain = CinemaChain.identify(from: name)
                return CinemaTheater(
                    id: identifier,
                    name: name,
                    chain: chain,
                    coordinate: coordinate,
                    address: CinemaMapKitBridge.addressLine(of: item),
                    phone: item.phoneNumber,
                    mapItem: item,
                    availability: .checkAtChain,
                    showtimes: []
                )
            }

            await enrichAMCShowtimes(filmTitle: filmTitle, date: Date(), userCoordinate: coord)
        } catch {
            lastError = error.localizedDescription
            theaters = []
        }
    }

    func refreshAMCShowtimes(filmTitle: String, date: Date) async {
        guard let coord = userCoordinate else { return }
        await enrichAMCShowtimes(filmTitle: filmTitle, date: date, userCoordinate: coord)
    }

    func forceRefreshAMCShowtimes(filmTitle: String, date: Date) async {
        guard let coord = userCoordinate else { return }
        isSearching = true
        theaters = theaters.filter { $0.chain != .amc }
        amcEverHadResults = false
        amcSearchCompleted = false
        dataLastUpdated = nil
        defer { isSearching = false }
        await enrichAMCShowtimes(filmTitle: filmTitle, date: date, userCoordinate: coord, forceRefresh: true)
    }

    private func enrichAMCShowtimes(filmTitle: String, date: Date, userCoordinate: CLLocationCoordinate2D, forceRefresh: Bool = false) async {
        let result = await AMCShowtimesService.fetchShowtimes(
            filmTitle: filmTitle,
            date: date,
            lat: userCoordinate.latitude,
            lon: userCoordinate.longitude,
            forceRefresh: forceRefresh
        )

        guard result.succeeded else { return }

        // Remove any existing AMC entries — we'll rebuild from the API response.
        let nonAMC = theaters.filter { $0.chain != .amc }

        // Build CinemaTheater entries from the API response, using API coordinates
        // or falling back to the user's location if the API didn't return them.
        // Distance filtering is handled in the view so the user can adjust the radius.
        let apiTheaters: [CinemaTheater] = result.entries.compactMap { entry in
            guard !entry.showtimes.isEmpty else { return nil }
            let coord: CLLocationCoordinate2D
            if let lat = entry.lat, let lon = entry.lon {
                coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            } else {
                coord = userCoordinate
            }
            let identifier = "amc|\(entry.name)"
            return CinemaTheater(
                id: identifier,
                name: entry.name,
                chain: .amc,
                coordinate: coord,
                address: nil,
                phone: nil,
                mapItem: nil,
                availability: .showtimesConfirmed,
                showtimes: entry.showtimes
            )
        }

        if !apiTheaters.isEmpty { amcEverHadResults = true }
        amcSearchCompleted = true
        dataLastUpdated = result.dataFetchedAt ?? Date()
        theaters = nonAMC + apiTheaters
    }

    private func normalizedName(_ name: String) -> String {
        name
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func fetchOneShotLocation() async -> CLLocation? {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            break
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
                return nil
            }
        default:
            return nil
        }

        return await withCheckedContinuation { continuation in
            pendingContinuation = continuation
            manager.requestLocation()
        }
    }

    private func resolveCountry(for location: CLLocation) async {
        countryCode = await CinemaMapKitBridge.resolveCountryCode(for: location)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.authorizationStatus = status
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in
            self.pendingContinuation?.resume(returning: location)
            self.pendingContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.pendingContinuation?.resume(returning: nil)
            self.pendingContinuation = nil
            self.lastError = error.localizedDescription
        }
    }

    @MainActor
    func drivingTime(from user: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async -> TimeInterval? {
        let source = CinemaMapKitBridge.makeMapItem(coordinate: user, name: nil)
        let dest = CinemaMapKitBridge.makeMapItem(coordinate: destination, name: nil)
        let request = MKDirections.Request()
        request.source = source
        request.destination = dest
        request.transportType = .automobile
        do {
            let response = try await MKDirections(request: request).calculateETA()
            return response.expectedTravelTime
        } catch {
            return nil
        }
    }
}
