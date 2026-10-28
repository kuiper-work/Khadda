import SwiftUI
import MapKit
import CoreLocation
import CoreMotion

// MARK: - StatusDotView
/// A reusable status indicator dot component.
/// Displays a green dot with a pulsating aura when active (`isActive == true`)
/// or a solid grey dot when standby/inactive (`isActive == false`).
struct StatusDotView: View {
    /// Controls whether the indicator represents an active state (green/pulsating) or inactive state (grey).
    var isActive: Bool
    
    /// State variable animating the expanding aura ring scale and opacity.
    @State private var isPulsating = false

    var body: some View {
        ZStack {
            // Expanding aura ring (rendered only when active)
            if isActive {
                Circle()
                    .fill(Color.green.opacity(0.35))
                    .frame(width: 18, height: 18)
                    .scaleEffect(isPulsating ? 1.6 : 0.8)
                    .opacity(isPulsating ? 0.0 : 0.9)
            }
            
            // Core solid dot indicator
            Circle()
                .fill(isActive ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
        }
        .onAppear {
            if isActive {
                startPulsatingAnimation()
            }
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                startPulsatingAnimation()
            } else {
                isPulsating = false
            }
        }
    }
    
    /// Starts the continuous smooth pulse animation loop for the outer aura ring.
    private func startPulsatingAnimation() {
        withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
            isPulsating = true
        }
    }
}

// MARK: - CodableCoordinate (Helper for CLLocationCoordinate2D)
/// A Codable wrapper for `CLLocationCoordinate2D` to allow encoding & persistence to JSON.
struct CodableCoordinate: Codable {
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees

    init(coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    /// Converts back to standard CoreLocation `CLLocationCoordinate2D`.
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - RoadSegment Model
/// Represents a single recorded road segment between two GPS coordinate updates with an associated bumpiness variance score.
struct RoadSegment: Identifiable, Codable {
    var id = UUID()
    let startCoordinate: CodableCoordinate
    let endCoordinate: CodableCoordinate
    let bumpinessScore: Double
}

// MARK: - Track Model
/// Represents a complete recorded trip session containing aggregated metrics and individual road segments.
struct Track: Identifiable, Codable {
    let id: UUID
    let date: Date
    let distance: CLLocationDistance
    let avgBumpiness: Double
    let segments: [RoadSegment]

    init(id: UUID = UUID(), date: Date, distance: CLLocationDistance, avgBumpiness: Double, segments: [RoadSegment]) {
        self.id = id
        self.date = date
        self.distance = distance
        self.avgBumpiness = avgBumpiness
        self.segments = segments
    }
}

// MARK: - Map Overlay Render Helpers
/// Renders circle overlays on the map.
func drawCircleOverPolyline(_ overlay: MKCircle) -> MKOverlayRenderer {
    let renderer = MKCircleRenderer(circle: overlay)
    renderer.strokeColor = .systemBlue
    renderer.fillColor = .systemTeal
    renderer.lineWidth = 2
    return renderer
}

/// Renders road segment polylines with colors corresponding to bumpiness categories.
func drawPolyline(_ overlay: MKPolyline) -> MKOverlayRenderer {
    let renderer = MKPolylineRenderer(polyline: overlay)
    let colorString = overlay.title ?? "green"
    switch colorString {
    case "green": renderer.strokeColor = .green
    case "orange": renderer.strokeColor = .orange
    case "red": renderer.strokeColor = .red
    case "darkRed": renderer.strokeColor = .init(red: 0.5, green: 0, blue: 0, alpha: 1.0)
    case "black": renderer.strokeColor = .black
    default: renderer.strokeColor = .gray
    }
    return renderer
}

// MARK: - BumpinessColor Extension
extension Double {
    /// Extension helper returning the SwiftUI Color associated with this bumpiness score.
    func bumpinessColor() -> Color {
        BumpinessCategory.category(for: self).color
    }
}

// MARK: - LocationAndMotionManager
/// Main location & motion telemetry manager.
/// Integrates CoreLocation (GPS position/speed) with CoreMotion accelerometer variance computation and activity classification.
@MainActor
@Observable
class LocationAndMotionManager: NSObject, CLLocationManagerDelegate {
    var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    private(set) var currentSpeed: CLLocationSpeed = 0.0
    private(set) var currentBumpiness: Double = 0.0
    private(set) var roadSegments: [RoadSegment] = []
    private(set) var isTracking: Bool = false
    private(set) var isManualTracking: Bool = false
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var motionAuthorizationStatus: CMAuthorizationStatus = .notDetermined
    
    private(set) var currentActivityType: String = "Unknown"
    var autoTrackingEnabled: Bool = true // User preference for automatic start/stop

    private(set) var totalDistance: CLLocationDistance = 0.0
    private(set) var averageBumpiness: Double = 0.0

    var savedTracks: [Track] = []
    var selectedSegmentID: UUID? = nil

    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()
    private let activityManager = CMMotionActivityManager()
    
    private var lastLocation: CLLocation?
    private var locationAccuracy: CLLocationAccuracy = kCLLocationAccuracyKilometer
    private var bumpinessEngine = BumpinessEngine(windowSize: 50)
    private let accelerometerUpdateInterval: TimeInterval = 1.0 / 50.0

    override init() {
        super.init()
        locationManager.delegate = self
        //locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation // High accuracy for path drawing
        locationManager.activityType = .automotiveNavigation // Optimize for driving
        
        // --- Crucial for background tracking ---
        locationManager.allowsBackgroundLocationUpdates = true // Allow location updates in background
        locationManager.pausesLocationUpdatesAutomatically = false // Prevent system from pausing updates
        // --- End background tracking setup ---

        // See if we can use the cached location
        if let cached = locationManager.location {
            region = MKCoordinateRegion(
                center: cached.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            )
        }
        // Initial check for motion authorization status
        motionAuthorizationStatus = CMMotionActivityManager.authorizationStatus()

        // Start monitoring activity updates
        startActivityUpdates()
            
        // Load saved tracks on initialization
        loadSavedTracks()
    }

    func setInitialRegionToUserLocation() {
        locationManager.requestLocation()
    }
    
    /// Starts recording a ride session.
    /// - Parameter isManual: Set to `true` when manually initiated via the UI menu to prevent auto-stop triggers on non-automotive activity.
    func startTracking(isManual: Bool = false) {
        guard (authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse) else {
            print("Location services not authorized.")
            return
        }
        
        guard motionAuthorizationStatus == .authorized else {
            print("Motion activity not authorized.")
            return
        }

        guard !isTracking else { return }

        isTracking = true
        isManualTracking = isManual
        roadSegments.removeAll()
        lastLocation = nil
        bumpinessEngine.reset()
        currentBumpiness = 0.0
        totalDistance = 0.0
        averageBumpiness = 0.0
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.startUpdatingLocation()

        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = accelerometerUpdateInterval
            motionManager.startAccelerometerUpdates(to: .main) { [weak self] (data, error) in
                guard let self = self, let accelerationData = data else { return }
                self.processAccelerometerData(accelerationData)
            }
        } else {
            print("Accelerometer is not available.")
        }
        print("Tracking started. Manual mode: \(isManual)")
        
        UIApplication.shared.isIdleTimerDisabled = true
    }

    /// Stops tracking, computes average bumpiness score across segments, saves track to disk, and restores idle timer.
    func stopTracking() {
        guard isTracking else { return }

        isTracking = false
        isManualTracking = false
        locationManager.stopUpdatingLocation()
        motionManager.stopAccelerometerUpdates()
        
        if !roadSegments.isEmpty {
            let totalBumpiness = roadSegments.reduce(0) { $0 + $1.bumpinessScore }
            averageBumpiness = totalBumpiness / Double(roadSegments.count)
        } else {
            averageBumpiness = 0.0
        }

        print("Tracking stopped. Total segments: \(roadSegments.count)")
        saveCurrentTrack()
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
    func requestPermissions() {
        let currentStatus = locationManager.authorizationStatus

        switch currentStatus {
        case .notDetermined, .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        case .denied, .restricted:
            print("Location services denied or restricted.")
        default:
            break
        }
    }

    /// Ingests 3-axis accelerometer data into the BumpinessEngine and updates currentBumpiness.
    private func processAccelerometerData(_ accelerationData: CMAccelerometerData) {
        currentBumpiness = bumpinessEngine.addSample(
            x: accelerationData.acceleration.x,
            y: accelerationData.acceleration.y,
            z: accelerationData.acceleration.z
        )
    }
    
    /// Starts CMMotionActivityManager updates to automatically start/stop tracking when automotive driving is detected.
    private func startActivityUpdates() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            print("Motion Activity is not available on this device.")
            currentActivityType = "Not Available"
            return
        }
        
        activityManager.startActivityUpdates(to: .main) { [weak self] (activity) in
            guard let self = self, let activity = activity else { return }
            
            self.motionAuthorizationStatus = CMMotionActivityManager.authorizationStatus()
            
            if activity.automotive {
                self.currentActivityType = "Driving"
            } else if activity.walking {
                self.currentActivityType = "Walking"
            } else if activity.running {
                self.currentActivityType = "Running"
            } else if activity.cycling {
                self.currentActivityType = "Cycling"
            } else if activity.stationary {
                self.currentActivityType = "Stationary"
            } else {
                self.currentActivityType = "Unknown"
            }
            
            // Auto-tracking logic: trigger start when driving, stop when stationary or walking (unless manually overridden)
            if self.autoTrackingEnabled && !self.isManualTracking {
                if activity.automotive && activity.confidence != .low {
                    if !self.isTracking {
                        self.startTracking(isManual: false)
                    }
                } else if (activity.walking || activity.running || activity.cycling || activity.stationary) && activity.confidence != .low {
                    if self.isTracking {
                        self.stopTracking()
                    }
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }

        region = MKCoordinateRegion(center: newLocation.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
        currentSpeed = newLocation.speed > 0 ? newLocation.speed : 0.0

        if let lastLoc = lastLocation {
            totalDistance += newLocation.distance(from: lastLoc)

            let segment = RoadSegment(
                startCoordinate: CodableCoordinate(coordinate: lastLoc.coordinate),
                endCoordinate: CodableCoordinate(coordinate: newLocation.coordinate),
                bumpinessScore: currentBumpiness
            )
            roadSegments.append(segment)
        }
        lastLocation = newLocation
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus != .authorizedAlways && authorizationStatus != .authorizedWhenInUse && isTracking {
            stopTracking()
        } else {
            setInitialRegionToUserLocation()
        }
    }

    // MARK: Persistence Helpers
    func tracksDirectoryURL() throws -> URL {
        try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Tracks")
    }

    func trackFileURL(for id: UUID) throws -> URL {
        try tracksDirectoryURL().appendingPathComponent("\(id.uuidString).json")
    }

    private func saveCurrentTrack() {
        let newTrack = Track(
            date: Date(),
            distance: totalDistance,
            avgBumpiness: averageBumpiness,
            segments: roadSegments
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(newTrack)
            
            let directoryURL = try tracksDirectoryURL()
            if !FileManager.default.fileExists(atPath: directoryURL.path) {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            }
            
            let fileURL = try trackFileURL(for: newTrack.id)
            try data.write(to: fileURL)
            
            DispatchQueue.main.async {
                self.savedTracks.append(newTrack)
                self.savedTracks.sort { $0.date > $1.date }
                print("Track saved successfully to: \(fileURL.lastPathComponent)")
            }
        } catch {
            print("Failed to save track: \(error.localizedDescription)")
        }
    }

    func loadSavedTracks() {
        do {
            let directoryURL = try tracksDirectoryURL()
            guard FileManager.default.fileExists(atPath: directoryURL.path) else {
                print("Tracks directory does not exist, no tracks to load.")
                return
            }

            let fileURLs = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                .filter { $0.pathExtension == "json" }

            var loadedTracks: [Track] = []
            let decoder = JSONDecoder()

            for fileURL in fileURLs {
                do {
                    let data = try Data(contentsOf: fileURL)
                    let track = try decoder.decode(Track.self, from: data)
                    loadedTracks.append(track)
                } catch {
                    print("Failed to load track from \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async {
                self.savedTracks = loadedTracks.sorted { $0.date > $1.date }
                print("Loaded \(self.savedTracks.count) tracks.")
            }
        } catch {
            print("Failed to load tracks: \(error.localizedDescription)")
        }
    }
}

// MARK: - MapViewCoordinator
/// Coordinator acting as delegate for `MKMapView`. Manages polyline rendering, tap gesture interaction, and pin annotation callouts.
class MapViewCoordinator: NSObject, MKMapViewDelegate {
    var parent: MapView

    init(_ parent: MapView) {
        self.parent = parent
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        let identifier = "BumpinessAnnotation"
        var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
        if view == nil {
            view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view?.canShowCallout = true
            view?.glyphText = "⛰️"
            view?.markerTintColor = .systemBlue
        } else {
            view?.annotation = annotation
        }
        return view
    }
    
    func presentCallout(for annotation: MKAnnotation, on mapView: MKMapView) {
        mapView.selectAnnotation(annotation, animated: true)
    }

    @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
        guard let mapView = gesture.view as? MKMapView else { return }
        let point = gesture.location(in: mapView)
        for overlay in mapView.overlays {
            guard let polyline = overlay as? MKPolyline else { continue }
            let renderer = mapView.renderer(for: polyline) as? MKPolylineRenderer
            let mapPoint = MKMapPoint(mapView.convert(point, toCoordinateFrom: mapView))
            let rendererPoint = renderer?.point(for: mapPoint) ?? .zero
            if let path = renderer?.path {
                let tapPath = path.copy(strokingWithWidth: max(renderer?.lineWidth ?? 5, 20), lineCap: .round, lineJoin: .round, miterLimit: 0)
                if tapPath.contains(rendererPoint) {
                    if let idString = polyline.subtitle, let id = UUID(uuidString: idString) {
                        parent.selectedSegmentID = id
                        mapView.removeOverlays(mapView.overlays)
                        mapView.addOverlays([overlay] + mapView.overlays)
                    }
                    return
                }
            }
        }
        parent.selectedSegmentID = nil
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        switch overlay {
        case let overlay as MKCircle:
            return drawCircleOverPolyline(overlay)
        case let overlay as MKPolyline:
            return drawPolyline(overlay)
        default:
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - MapView (UIKit Wrapper for SwiftUI)
/// Reusable SwiftUI wrapper for `MKMapView` supporting coordinate region bindings, polylines, and selected segment annotations.
struct MapView: UIViewRepresentable {
    @Binding var regionToDisplay: MKCoordinateRegion
    @Binding var selectedSegmentID: UUID?
    var segments: [RoadSegment]
    var showsUserLocation: Bool = true

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = showsUserLocation
        
        mapView.addOverlay(MKCircle())
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(MapViewCoordinator.handleMapTap(_:)))
        mapView.addGestureRecognizer(tap)
        
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.setRegion(regionToDisplay, animated: true)
        uiView.removeOverlays(uiView.overlays)
        
        let movingCircleOverPolyline = MKCircle(center: regionToDisplay.center, radius: 40)
        uiView.addOverlay(movingCircleOverPolyline)
        
        for segment in segments {
            let coordinates = [segment.startCoordinate.clCoordinate, segment.endCoordinate.clCoordinate]
            let polyline = MKPolyline(coordinates: coordinates, count: 2)
            polyline.title = segment.bumpinessScore.bumpinessColor().description
            polyline.subtitle = segment.id.uuidString
            uiView.addOverlay(polyline)
        }
        
        let existing = uiView.annotations.filter { ($0.subtitle ?? nil) == "bumpiness" }
        uiView.removeAnnotations(existing)

        if let selectedID = selectedSegmentID, let selected = segments.first(where: { $0.id == selectedID }) {
            let start = selected.startCoordinate.clCoordinate
            let end = selected.endCoordinate.clCoordinate
            let mid = CLLocationCoordinate2D(latitude: (start.latitude + end.latitude) / 2.0,
                                             longitude: (start.longitude + end.longitude) / 2.0)
            let annotation = MKPointAnnotation()
            annotation.coordinate = mid
            let category = BumpinessCategory.category(for: selected.bumpinessScore)
            annotation.title = "\(category.rawValue) (\(String(format: "%.4f", selected.bumpinessScore)))"
            annotation.subtitle = "bumpiness"
            uiView.addAnnotation(annotation)
            context.coordinator.presentCallout(for: annotation, on: uiView)
        }
    }

    func makeCoordinator() -> MapViewCoordinator {
        MapViewCoordinator(self)
    }
}

// MARK: - ContentView (Main SwiftUI View)
/// Main application view presenting the full-screen map, live telemetry activity card, and top status bar.
struct ContentView: View {
    @State private var manager = LocationAndMotionManager()
    @State private var showingPermissionAlert = false

    /// Computes whether active driving and recording is currently taking place.
    var isDrivingAndTracking: Bool {
        manager.isTracking && manager.currentActivityType == "Driving"
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Map Background View
                MapView(regionToDisplay: $manager.region, selectedSegmentID: $manager.selectedSegmentID, segments: manager.roadSegments)
                    .ignoresSafeArea()
                
                // Map Overlay UI Controls
                VStack {
                    if manager.isTracking {
                        ActivityView(
                            currentSpeed: manager.currentSpeed,
                            currentBumpiness: manager.currentBumpiness,
                            currentActivityType: manager.currentActivityType
                        )
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    } else if !manager.roadSegments.isEmpty {
                        SummaryView(
                            totalDistance: manager.totalDistance,
                            avgBumpiness: manager.averageBumpiness
                        )
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    Spacer()
                    
                    // Bottom Controls Bar (shown during active tracking)
                    if manager.isTracking {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                manager.stopTracking()
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "stop.fill")
                                Text("Stop Recording")
                                    .fontWeight(.bold)
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 28)
                            .background(Color.red, in: Capsule())
                            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
                        }
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Principal Top Header with Status Dot & Car Driving Icon
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        StatusDotView(isActive: isDrivingAndTracking)
                        
                        Image(systemName: "car.side.fill")
                            .font(.title3)
                            .foregroundColor(isDrivingAndTracking ? .primary : .gray)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: TrackHistoryView(manager: manager)) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.headline)
                    }
                }
                
                // Manual Start Option Menu for non-car rides or testing
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button(action: {
                            withAnimation {
                                if manager.isTracking {
                                    manager.stopTracking()
                                } else {
                                    manager.startTracking(isManual: true)
                                }
                            }
                        }) {
                            Label(
                                manager.isTracking ? "Stop Tracking" : "Start Manual Trip",
                                systemImage: manager.isTracking ? "stop.circle" : "record.circle"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.headline)
                    }
                }
            }
        }
        .onAppear {
            manager.requestPermissions()
        }
        .alert("Permissions Required", isPresented: $showingPermissionAlert) {
            Button("OK") {
                if manager.authorizationStatus == .denied || manager.motionAuthorizationStatus == .denied {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } else {
                    manager.requestPermissions()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This app needs access to your location (Always or When In Use) and motion activity to track road bumpiness. Please grant permissions in Settings.")
        }
    }
}

#Preview {
    ContentView()
}
