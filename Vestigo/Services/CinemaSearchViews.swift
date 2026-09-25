import SwiftUI
import Foundation
#if canImport(MapKit)
import MapKit
#endif
#if canImport(CoreLocation)
import CoreLocation
#endif

struct CinemasNearYouSection: View {
    let filmTitle: String
    let releaseDate: Date?
    @ObservedObject var service: CinemaSearchService
    @Binding var selectedDate: Date
    let accentColor: Color

    @Environment(\.openURL) private var openURL
    @State private var selectedTheater: CinemaTheater?
    @State private var didAttemptLoad = false
    @State private var mapCameraPosition: MapCameraPosition = .automatic

    private var dateRange: ClosedRange<Date> {
        let today = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 14, to: today) ?? today
        return today...end
    }

    // AMC theatres with confirmed showtimes, sorted closest-first using the user's current location.
    private var displayedTheaters: [CinemaTheater] {
        let candidates = service.theaters.filter { $0.chain == .amc && !$0.showtimes.isEmpty }
        guard let userCoord = service.userCoordinate else {
            return candidates.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        let userLocation = CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude)
        return candidates.sorted { a, b in
            CLLocation(latitude: a.coordinate.latitude, longitude: a.coordinate.longitude).distance(from: userLocation) <
            CLLocation(latitude: b.coordinate.latitude, longitude: b.coordinate.longitude).distance(from: userLocation)
        }
    }

    private var dataAgeText: String? {
        guard let updated = service.dataLastUpdated else { return nil }
        let elapsed = Date().timeIntervalSince(updated)
        if elapsed < 60 { return "Just updated" }
        if elapsed < 3600 { return "Updated \(Int(elapsed / 60))m ago" }
        if elapsed < 86400 { return "Updated \(Int(elapsed / 3600))h ago" }
        return "Updated \(Int(elapsed / 86400))d ago"
    }

    // True when the film's release date is recent enough that it could plausibly
    // still be showing, even if no AMC results came back for the user's location.
    private var isLikelyInCinemas: Bool {
        guard let releaseDate else { return false }
        let cutoff = Calendar.current.date(byAdding: .day, value: -120, to: Date()) ?? Date()
        return releaseDate >= cutoff
    }

    // Reveal once AMC confirmed results, OR once the search completed for a film
    // that's likely still in cinemas (0 results = not near user, not "not showing").
    private var shouldReveal: Bool {
        guard service.userCoordinate != nil else { return false }
        return service.amcEverHadResults || (service.amcSearchCompleted && isLikelyInCinemas)
    }

    var body: some View {
        Group {
            if service.authorizationStatus == .denied || service.authorizationStatus == .restricted {
                locationDeniedSection
            } else if shouldReveal {
                visibleSection
            } else {
                Color.clear
                    .frame(height: 0)
                    .onAppear(perform: kickOffLoadIfNeeded)
            }
        }
        .onChange(of: selectedDate) { _, newValue in
            Task { await service.refreshAMCShowtimes(filmTitle: filmTitle, date: newValue) }
        }
        .onChange(of: service.authorizationStatus) { _, newValue in
            // If the user grants permission from Settings, retry the search automatically
            if newValue == .authorizedWhenInUse || newValue == .authorizedAlways {
                didAttemptLoad = false
                kickOffLoadIfNeeded()
            }
        }
        .sheet(item: $selectedTheater) { theater in
            CinemaInfoSheet(
                theater: theater,
                filmTitle: filmTitle,
                selectedDate: selectedDate,
                userCoordinate: service.userCoordinate,
                service: service,
                accentColor: accentColor
            )
            .presentationDetents([.medium, .large])
        }
    }

    private var visibleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AMC cinemas nearby")
                        .sectionTitle()
                    if let age = dataAgeText {
                        Text(age)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                // Disable refresh if data is less than 24h old — no point bypassing the cache
                let dataIsStale = service.dataLastUpdated.map { Date().timeIntervalSince($0) >= 86400 } ?? false
                let canRefresh = !service.isSearching && dataIsStale
                Button {
                    Task { await service.forceRefreshAMCShowtimes(filmTitle: filmTitle, date: selectedDate) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .liquidGlass(cornerRadius: 15)
                }
                .buttonStyle(.plain)
                .disabled(!canRefresh)
                .opacity(canRefresh ? 1 : 0.4)
            }
            theaterSection
        }
        .onAppear(perform: kickOffLoadIfNeeded)
    }

    private var locationDeniedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AMC cinemas nearby")
                .sectionTitle()
            HStack(spacing: 14) {
                Image(systemName: "location.slash.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Location access required")
                        .font(.subheadline.bold())
                    Text("Enable location in Settings to find AMC theatres near you.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Settings") {
                    if let url = URL(string: "app-settings:") {
                        openURL(url)
                    }
                }
                .font(.caption.bold())
                .foregroundStyle(accentColor)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(cornerRadius: 16)
        }
    }

    private func kickOffLoadIfNeeded() {
        guard !didAttemptLoad else { return }
        didAttemptLoad = true
        AnalyticsService.shared.track(.cinemaSearchUsed)
        Task { await service.loadNearbyTheaters(filmTitle: filmTitle) }
    }

    private var dayPills: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<14, id: \.self) { offset in
                    let date = cal.date(byAdding: .day, value: offset, to: today) ?? today
                    let isSelected = cal.isDate(date, inSameDayAs: selectedDate)
                    let dayNum = cal.component(.day, from: date)
                    let dayName: String = {
                        if offset == 0 { return "Today" }
                        let f = DateFormatter(); f.dateFormat = "EEE"; return f.string(from: date)
                    }()
                    Button {
                        selectedDate = date
                    } label: {
                        VStack(spacing: 1) {
                            Text(dayName)
                                .font(.system(size: 10, weight: .semibold))
                            Text("\(dayNum)")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .frame(width: 46, height: 48)
                        .foregroundStyle(isSelected ? .white : .primary)
                        .background(isSelected ? accentColor : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .liquidGlass(cornerRadius: 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var theaterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            dayPills

            if displayedTheaters.isEmpty {
                let emptyMessage = "No AMC showtimes found near you for \(filmTitle) on this date."
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                CinemaMapView(
                    theaters: displayedTheaters,
                    userCoordinate: service.userCoordinate,
                    accentColor: accentColor,
                    cameraPosition: $mapCameraPosition,
                    onSelect: { theater in selectedTheater = theater }
                )
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                )

                Text("Tap any AMC pin to see showtimes and open its booking page.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                theaterList
            }
        }
    }

    private var theaterList: some View {
        VStack(spacing: 10) {
            ForEach(displayedTheaters.prefix(10)) { theater in
                Button {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        mapCameraPosition = .region(MKCoordinateRegion(
                            center: theater.coordinate,
                            latitudinalMeters: 3_000,
                            longitudinalMeters: 3_000
                        ))
                    }
                    selectedTheater = theater
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: theater.availability == .showtimesConfirmed ? "sparkles" : "mappin.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(theater.availability == .showtimesConfirmed ? accentColor : .secondary)
                            .frame(width: 30, height: 30)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(theater.name)
                                .font(.headline.bold())
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text(theater.availability == .showtimesConfirmed
                                 ? "Showtimes available"
                                 : "Check availability")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
                .liquidGlass(cornerRadius: 20)
            }
        }
    }
}

struct CinemaMapView: View {
    let theaters: [CinemaTheater]
    let userCoordinate: CLLocationCoordinate2D?
    let accentColor: Color
    @Binding var cameraPosition: MapCameraPosition
    let onSelect: (CinemaTheater) -> Void

    var body: some View {
        Map(position: $cameraPosition) {
            if let userCoordinate {
                Annotation("You", coordinate: userCoordinate) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }

            ForEach(theaters) { theater in
                Annotation("", coordinate: theater.coordinate) {
                    Button {
                        onSelect(theater)
                    } label: {
                        pin(for: theater)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .onAppear {
            guard let userCoordinate else { return }
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: userCoordinate,
                    latitudinalMeters: 40_000,
                    longitudinalMeters: 40_000
                )
            )
        }
    }

    @ViewBuilder
    private func pin(for theater: CinemaTheater) -> some View {
        let confirmed = theater.availability == .showtimesConfirmed
        let size: CGFloat = confirmed ? 20 : 14
        ZStack {
            Circle()
                .fill(confirmed ? accentColor : .secondary.opacity(0.6))
            Image(systemName: confirmed ? "sparkles" : "mappin")
                .font(.system(size: confirmed ? 9 : 7, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay(
            Circle().stroke(.white, lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
}

struct CinemaInfoSheet: View {
    let theater: CinemaTheater
    let filmTitle: String
    let selectedDate: Date
    let userCoordinate: CLLocationCoordinate2D?
    @ObservedObject var service: CinemaSearchService
    let accentColor: Color

    @Environment(\.openURL) private var openURL
    @State private var drivingSeconds: TimeInterval?
    @State private var didLoadDriving = false
    @State private var showMapsChoice = false

    var body: some View {
        ZStack {
            AppBackground(settings: .init())
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    distanceRow

                    if theater.availability == .showtimesConfirmed {
                        if theater.showtimes.isEmpty {
                            StatusBubble(
                                title: "No showtimes yet",
                                text: "AMC hasn't published showtimes for this film on the selected date."
                            )
                        } else {
                            showtimeGrid
                        }
                    } else {
                        checkAtChainBubble
                    }

                    openInMapsButton
                }
                .padding(18)
            }
        }
        .task {
            guard !didLoadDriving, let user = userCoordinate else { return }
            didLoadDriving = true
            drivingSeconds = await service.drivingTime(from: user, to: theater.coordinate)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(theater.name)
                .font(.title2.bold())
            if let address = theater.address {
                Text(address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var distanceRow: some View {
        HStack(spacing: 14) {
            if let user = userCoordinate {
                let (mi, km) = distances(user: user, dest: theater.coordinate)
                infoChip(icon: "location.circle", label: String(format: "%.1f mi", mi))
                infoChip(icon: "location.north.line.fill", label: String(format: "%.1f km", km))
            }
            if let drivingSeconds {
                infoChip(icon: "car.fill", label: formatDuration(drivingSeconds))
            }
        }
    }

    private var showtimeGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Showtimes")
                    .font(.headline.bold())
                Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            let now = Date()
            let upcoming = theater.showtimes.filter { $0.startTime > now }
            if upcoming.isEmpty {
                Text("All showtimes for this date have passed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: [GridItem(.flexible())], spacing: 10) {
                    ForEach(upcoming) { showtime in
                        Button {
                            if let url = showtime.bookingURL {
                                openURL(url)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(showtime.startTime.formatted(date: .omitted, time: .shortened))
                                    .font(.headline.bold())
                                if let format = showtime.format, !format.isEmpty {
                                    Text(format)
                                        .font(.caption.bold())
                                        .foregroundStyle(accentColor)
                                }
                                if !showtime.accessibility.isEmpty {
                                    Text(showtime.accessibility.joined(separator: " · "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .liquidGlass(cornerRadius: 16)
                    }
                }
            }
        }
    }

    private var checkAtChainBubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Check availability")
                .font(.headline.bold())
            Text("Open the theater's website to see if \(filmTitle) is showing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                openChainSite()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Open \(theater.chain.displayName)")
                        .font(.subheadline.bold())
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .liquidGlass(cornerRadius: 22)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 22)
    }

    private var openInMapsButton: some View {
        Button {
            showMapsChoice = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "map.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text("Open in Maps")
                    .font(.subheadline.bold())
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .liquidGlass(cornerRadius: 22)
        }
        .buttonStyle(.plain)
        .confirmationDialog("Open in Maps", isPresented: $showMapsChoice, titleVisibility: .visible) {
            Button("Apple Maps") { openInAppleMaps() }
            Button("Google Maps") { openInGoogleMaps() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func infoChip(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.bold())
            Text(label)
                .font(.caption.bold())
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .liquidGlass(cornerRadius: 15)
    }

    private func distances(user: CLLocationCoordinate2D, dest: CLLocationCoordinate2D) -> (mi: Double, km: Double) {
        let a = CLLocation(latitude: user.latitude, longitude: user.longitude)
        let b = CLLocation(latitude: dest.latitude, longitude: dest.longitude)
        let meters = a.distance(from: b)
        let km = meters / 1000
        let mi = meters / 1609.34
        return (mi, km)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return "\(minutes) min drive"
        }
        let hours = minutes / 60
        let remaining = minutes % 60
        return remaining == 0 ? "\(hours)h drive" : "\(hours)h \(remaining)m drive"
    }

    private func openChainSite() {
        if let appURL = theater.chain.searchAppURL(filmTitle: filmTitle),
           UIApplication.shared.canOpenURL(appURL) {
            openURL(appURL)
            return
        }
        if let webURL = theater.chain.searchWebURL(filmTitle: filmTitle) {
            openURL(webURL)
        }
    }

    private func openInAppleMaps() {
        let item = theater.mapItem ?? CinemaMapKitBridge.makeMapItem(coordinate: theater.coordinate, name: theater.name)
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    private func openInGoogleMaps() {
        let lat = theater.coordinate.latitude
        let lon = theater.coordinate.longitude
        if let url = URL(string: "https://maps.google.com/maps?daddr=\(lat),\(lon)") {
            openURL(url)
        }
    }
}

/// Small compatibility bridge for iOS 26 MapKit API deprecations.
/// New API used on iOS 26+, deprecated MKPlacemark/CLGeocoder path retained for older OSes.
enum CinemaMapKitBridge {
    static func makeMapItem(coordinate: CLLocationCoordinate2D, name: String?) -> MKMapItem {
        if #available(iOS 26.0, *) {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let item = MKMapItem(location: location, address: nil)
            item.name = name
            return item
        } else {
            return makeMapItemLegacy(coordinate: coordinate, name: name)
        }
    }

    static func coordinate(of mapItem: MKMapItem) -> CLLocationCoordinate2D {
        if #available(iOS 26.0, *) {
            return mapItem.location.coordinate
        } else {
            return coordinateLegacy(of: mapItem)
        }
    }

    static func addressLine(of mapItem: MKMapItem) -> String? {
        if #available(iOS 26.0, *) {
            return mapItem.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
                ?? mapItem.address?.fullAddress
        } else {
            return addressLineLegacy(of: mapItem)
        }
    }

    static func resolveCountryCode(for location: CLLocation) async -> String? {
        if #available(iOS 26.0, *) {
            guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
            do {
                let mapItems = try await request.mapItems
                return mapItems.first?.addressRepresentations?.region?.identifier
            } catch {
                return nil
            }
        } else {
            return await resolveCountryCodeLegacy(for: location)
        }
    }

    @available(iOS, deprecated: 26.0, message: "Deprecated MKPlacemark path; use MKMapItem(location:address:) on iOS 26+.")
    private static func makeMapItemLegacy(coordinate: CLLocationCoordinate2D, name: String?) -> MKMapItem {
        let placemark = MKPlacemark(coordinate: coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = name
        return item
    }

    @available(iOS, deprecated: 26.0, message: "Deprecated placemark accessor; use MKMapItem.location on iOS 26+.")
    private static func coordinateLegacy(of mapItem: MKMapItem) -> CLLocationCoordinate2D {
        mapItem.placemark.coordinate
    }

    @available(iOS, deprecated: 26.0, message: "Deprecated placemark accessor; use MKMapItem.addressRepresentations on iOS 26+.")
    private static func addressLineLegacy(of mapItem: MKMapItem) -> String? {
        mapItem.placemark.title
    }

    @available(iOS, deprecated: 26.0, message: "Deprecated CLGeocoder path; use MKReverseGeocodingRequest on iOS 26+.")
    private static func resolveCountryCodeLegacy(for location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            return placemarks.first?.isoCountryCode
        } catch {
            return nil
        }
    }
}
