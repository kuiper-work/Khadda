import SwiftUI
import MapKit
import CoreLocation
import CoreMotion

// MARK: - CodableCoordinate (Helper for CLLocationCoordinate2D)
struct CodableCoordinate: Codable {
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees

    init(coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    // Getter method to dynamically retrieve the coordinates
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
}

// MARK: - RoadSegment Model
// Represents a segment of the road with its coordinates and calculated bumpiness.
struct RoadSegment: Identifiable, Codable { // Now Codable
    var id = UUID()
    let startCoordinate: CodableCoordinate // Use CodableCoordinate
    let endCoordinate: CodableCoordinate   // Use CodableCoordinate
    let bumpinessScore: Double // Higher score means bumpier
}

// MARK: - Track Model (New for persistence)
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

// MARK: - BumpinessColor Extension
// Helper to map bumpiness score to a specific color.
extension Double {
    func bumpinessColor() -> Color {
        // Define thresholds for bumpiness scores to map to colors
        // These values will likely need calibration based on real-world testing
        if self < 0.005 { // Very smooth (adjusted threshold)
            return .green
        } else if self < 0.015 { // Smooth (adjusted threshold)
            return .orange
        } else if self < 0.03 { // Bumpy (adjusted threshold)
            return .red
        } else if self < 0.05 { // Very Bumpy (adjusted threshold)
            return .init(red: 0.5, green: 0, blue: 0) // Dark Red
        } else { // Extremely Bumpy / Pothole
            return .black
        }
    }
}

// MARK: - LocationAndMotionManager
// Manages CoreLocation and CoreMotion data acquisition.
@MainActor
@Observable
class LocationAndMotionManager: NSObject, CLLocationManagerDelegate {
    // MARK: Published Properties
    var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // Default to San Francisco
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    private(set) var currentSpeed: CLLocationSpeed = 0.0
    private(set) var currentBumpiness: Double = 0.0
    private(set) var roadSegments: [RoadSegment] = [] // To save them for later use
    private(set) var isTracking: Bool = false // Indicates if location/accelerometer updates are active
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var motionAuthorizationStatus: CMAuthorizationStatus = .notDetermined
    
    // New properties for activity detection
    private(set) var currentActivityType: String = "Unknown"
    var autoTrackingEnabled: Bool = true // User preference for automatic start/stop

    // New properties for summary
    private(set) var totalDistance: CLLocationDistance = 0.0
    private(set) var averageBumpiness: Double = 0.0

    // New: Stored tracks
    var savedTracks: [Track] = []
    var selectedSegmentID: UUID? = nil

    // MARK: Private Properties
    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()
    private let activityManager = CMMotionActivityManager()
    
    private var lastLocation: CLLocation?
    private var locationAccuracy: CLLocationAccuracy = kCLLocationAccuracyKilometer
    private var accelerometerDataBuffer: [Double] = []
    private let bufferSize = 50 // Increased buffer size for xbumpiness calculation (was 20)
    // Accelerometer provides 100 data points per second, 1 per each cycle. i.e. 1 data every 0.01 second (100 milliseconds)
    private let accelerometerUpdateInterval: TimeInterval = 1.0 / 100.0 // 50 Hz
    
    let deviceManagerActivityQueue = OperationQueue()

    
    // MARK: Initialization
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
        //startActivityUpdates()
            
        // Load saved tracks on initialization
        loadSavedTracks()
    }

    // MARK: Public Methods
    func setInitialRegionToUserLocation() {
        locationManager.requestLocation()
    }
    
    func startTracking() {
        // Ensure necessary permissions are granted before starting
        guard (authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse) else {
            print("Location services not authorized.")
            return
        }
        
        // Check for motion activity authorization (essential for automatic tracking)
        guard motionAuthorizationStatus == .authorized else {
            print("Motion activity not authorized.")
            return
        }

        guard !isTracking else { return } // Prevent starting if already tracking

        isTracking = true
        roadSegments.removeAll()
        lastLocation = nil
        accelerometerDataBuffer.removeAll()
        currentBumpiness = 0.0
        totalDistance = 0.0 // Reset total distance
        averageBumpiness = 0.0 // Reset average bumpiness
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.startUpdatingLocation()

        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = accelerometerUpdateInterval
            motionManager.startAccelerometerUpdates(to: .main) { [weak self] (data, error) in
                guard let self = self, let acceleration = data?.acceleration else { return }
                self.processAccelerometerData(acceleration)
            }
        } else {
            print("Device motion is not available.")
        }
        print("Tracking started.")
        
        // Prevent screen from going to sleep
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stopTracking() {
        guard isTracking else { return } // Prevent stopping if not tracking

        isTracking = false
        locationManager.stopUpdatingLocation()
        motionManager.stopDeviceMotionUpdates()
        
        // Calculate average bumpiness upon stopping
        if !roadSegments.isEmpty {
            let totalBumpiness = roadSegments.reduce(0) { $0 + $1.bumpinessScore }
            averageBumpiness = totalBumpiness / Double(roadSegments.count)
        } else {
            averageBumpiness = 0.0
        }

        print("Tracking stopped. Total segments: \(roadSegments.count)")
        
        // Save the completed track
        saveCurrentTrack()
        
        // Allow screen to go to sleep again
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
    func requestPermissions() {
        // Check current authorization status
        let currentStatus = locationManager.authorizationStatus

        switch currentStatus {
        case .notDetermined:
            // If not determined, request "Always" authorization directly.
            // This will typically show "Allow While Using App" and "Don't Allow" initially.
            // If the user chooses "Allow While Using App", they might get a second prompt later for "Always".
            // Or, they'll need to go to settings manually.
            locationManager.requestAlwaysAuthorization()
        case .authorizedWhenInUse:
            // If already authorized "When In Use", try to upgrade to "Always".
            // This might prompt the user again.
            locationManager.requestAlwaysAuthorization()
        case .denied, .restricted:
            // Permissions denied or restricted. App cannot get location.
            print("Location services denied or restricted. User needs to enable in settings.")
            // The alert in ContentView already handles directing to settings.
        default:
            break // Already authorizedAlways or unknown status
        }
        
        // Motion activity permission is typically implicitly granted with CoreMotion usage
        // but it's good to check its status.
        // CMMotionActivityManager.requestAuthorization() is not a public API.
        // The authorizationStatus is read-only.
        // If the user denies, you'll see .denied.
    }

    // MARK: Private Methods - Accelerometer Processing
    private func processAccelerometerData(_ acceleration: CMAcceleration) {
        // Using userAcceleration (gravity-removed) to get orientation-independent motion
        // Calculate magnitude of acceleration vector for detecting bumps regardless of phone orientation
        let magnitude = sqrt(acceleration.x * acceleration.x +
                           acceleration.y * acceleration.y +
                           acceleration.z * acceleration.z)
        accelerometerDataBuffer.append(magnitude)

        if accelerometerDataBuffer.count > bufferSize {
            accelerometerDataBuffer.removeFirst() // Keep buffer size constant
        }

        if accelerometerDataBuffer.count == bufferSize {
            // Calculate bumpiness as the variance of acceleration magnitude in the buffer
            let sum = accelerometerDataBuffer.reduce(0, +)
            let mean = sum / Double(bufferSize)
            let variance = accelerometerDataBuffer.map { pow($0 - mean, 2) }.reduce(0, +) / Double(bufferSize)
            currentBumpiness = variance // Variance as bumpiness score
        }
    }
    
    // MARK: Private Methods - Activity Detection
    private func startActivityUpdates() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            print("Motion Activity is not available on this device.")
            currentActivityType = "Not Available"
            return
        }
        
        activityManager.startActivityUpdates(to: .main) { [weak self] (activity) in
            guard let self = self, let activity = activity else { return }
            
            self.motionAuthorizationStatus = CMMotionActivityManager.authorizationStatus() // Update status
            
            // Update current activity type for UI display
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
            
            // Auto-tracking logic
            if self.autoTrackingEnabled {
                if activity.automotive && activity.confidence != .low {
                    // Start tracking if driving and not already tracking
                    if !self.isTracking {
                        self.startTracking()
                    }
                } else if (activity.walking || activity.running || activity.cycling || activity.stationary) && activity.confidence != .low {
                    // Stop tracking if activity is not automotive and currently tracking
                    if self.isTracking {
                        self.stopTracking()
                    }
                }
            }
        }
    }

    // MARK: CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }

        // Update map region to current location
        region = MKCoordinateRegion(center: newLocation.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
        currentSpeed = newLocation.speed > 0 ? newLocation.speed : 0.0 // Ensure speed is non-negative

        // Always add a segment if lastLocation exists to ensure continuous path drawing
        if let lastLoc = lastLocation {
            // Add distance to totalDistance
            totalDistance += newLocation.distance(from: lastLoc)

            let segment = RoadSegment(
                startCoordinate: CodableCoordinate(coordinate: lastLoc.coordinate), // Use CodableCoordinate
                endCoordinate: CodableCoordinate(coordinate: newLocation.coordinate), // Use CodableCoordinate
                bumpinessScore: currentBumpiness // Use the current bumpiness for this segment
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
        // If authorization changes, and we are tracking, re-evaluate
        if authorizationStatus != .authorizedAlways && authorizationStatus != .authorizedWhenInUse && isTracking {
            stopTracking() // Stop if permissions are revoked while tracking
        } else {
            setInitialRegionToUserLocation()
        }
    }

    // MARK: - Persistence Methods
    // Changed to internal access level
    func tracksDirectoryURL() throws -> URL {
        try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Tracks")
    }

    // Changed to internal access level
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
                self.savedTracks.append(newTrack) // Add to our in-memory list
                self.savedTracks.sort { $0.date > $1.date } // Sort by most recent first
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
                    // Optionally delete corrupted files
                    // try? FileManager.default.removeItem(at: fileURL)
                }
            }
            DispatchQueue.main.async {
                self.savedTracks = loadedTracks.sorted { $0.date > $1.date } // Sort by most recent first
                print("Loaded \(self.savedTracks.count) tracks.")
            }
        } catch {
            print("Failed to load tracks: \(error.localizedDescription)")
        }
    }
}

// MARK: - MapViewCoordinator
// MKMapViewDelegate for drawing polylines.
class MapViewCoordinator: NSObject, MKMapViewDelegate {
    var parent: MapView

    init(_ parent: MapView) {
        self.parent = parent
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        // Use a marker-style callout for the bumpiness popup
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
        // Ensure the annotation is visible and selected
        mapView.selectAnnotation(annotation, animated: true)
    }

    @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
        guard let mapView = gesture.view as? MKMapView else { return }
        let point = gesture.location(in: mapView)
        // Iterate overlays to find the first polyline whose renderer path contains the tap point
        for overlay in mapView.overlays {
            guard let polyline = overlay as? MKPolyline else { continue }
            let renderer = mapView.renderer(for: polyline) as? MKPolylineRenderer
            // Convert tap point to the renderer's coordinate space
            let mapPoint = MKMapPoint(mapView.convert(point, toCoordinateFrom: mapView))
            let rendererPoint = renderer?.point(for: mapPoint) ?? .zero
            if let path = renderer?.path {
                // Increase tappable width by stroking a wider path
                let tapPath = path.copy(strokingWithWidth: max(renderer?.lineWidth ?? 5, 20), lineCap: .round, lineJoin: .round, miterLimit: 0)
                if tapPath.contains(rendererPoint) {
                    // Found tapped polyline; update selected ID via parent binding
                    if let idString = polyline.subtitle, let id = UUID(uuidString: idString) {
                        parent.selectedSegmentID = id
                        // Trigger re-render by resetting overlays (force refresh)
                        mapView.removeOverlays(mapView.overlays)
                        mapView.addOverlays([overlay] + mapView.overlays)
                    }
                    return
                }
            }
        }
        // If no overlay hit, clear selection
        parent.selectedSegmentID = nil
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            // Determine base color from title
            let colorString = polyline.title ?? "green"
            switch colorString {
            case "green": renderer.strokeColor = .green
            case "orange": renderer.strokeColor = .orange
            case "red": renderer.strokeColor = .red
            case "darkRed": renderer.strokeColor = .init(red: 0.5, green: 0, blue: 0, alpha: 1.0)
            case "black": renderer.strokeColor = .black
            default: renderer.strokeColor = .gray
            }
            // Highlight if selected
            if let idString = polyline.subtitle, let id = UUID(uuidString: idString), id == parent.selectedSegmentID {
                renderer.lineWidth = 8
                renderer.strokeColor = .systemBlue
            } else {
                renderer.lineWidth = 5
            }
            renderer.lineCap = .round
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
}

// MARK: - MapView (UIKit Wrapper for SwiftUI)
// Wraps MKMapView for use in SwiftUI.
struct MapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    @Binding var selectedSegmentID: UUID?
    var segments: [RoadSegment] // Now takes an array of RoadSegment
    var showsUserLocation: Bool = true // Added to control user location dot for history view

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = showsUserLocation // Control based on parameter
        
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(MapViewCoordinator.handleMapTap(_:)))
        mapView.addGestureRecognizer(tap)
        
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.setRegion(region, animated: true)

        // Remove old overlays and add new ones
        uiView.removeOverlays(uiView.overlays)
        for segment in segments {
            let coordinates = [segment.startCoordinate.clCoordinate, segment.endCoordinate.clCoordinate] // Use clCoordinate
            let polyline = MKPolyline(coordinates: coordinates, count: 2)
            // Pass color as title for simplicity in MVP
            polyline.title = segment.bumpinessScore.bumpinessColor().description
            // Store the segment ID in subtitle for hit-testing and selection mapping
            polyline.subtitle = segment.id.uuidString
            uiView.addOverlay(polyline)
        }
        
        // Manage bumpiness popup annotation for selected segment
        // Remove existing bumpiness annotations we added previously
        let existing = uiView.annotations.filter { ($0.subtitle ?? nil) == "bumpiness" }
        uiView.removeAnnotations(existing)

        if let selectedID = selectedSegmentID, let selected = segments.first(where: { $0.id == selectedID }) {
            // Compute midpoint of the segment
            let start = selected.startCoordinate.clCoordinate
            let end = selected.endCoordinate.clCoordinate
            let mid = CLLocationCoordinate2D(latitude: (start.latitude + end.latitude) / 2.0,
                                             longitude: (start.longitude + end.longitude) / 2.0)
            let annotation = MKPointAnnotation()
            annotation.coordinate = mid
            annotation.title = String(format: "Bumpiness: %.5f", selected.bumpinessScore)
            annotation.subtitle = "bumpiness" // mark for later removal
            uiView.addAnnotation(annotation)
            // Present the callout
            context.coordinator.presentCallout(for: annotation, on: uiView)
        }
    }

    func makeCoordinator() -> MapViewCoordinator {
        MapViewCoordinator(self)
    }
}

// MARK: - ContentView (Main SwiftUI View)
struct ContentView: View {
    @State private var manager = LocationAndMotionManager()
    @State private var showingPermissionAlert = false

    var body: some View {
        NavigationStack { // Wrap in NavigationView
            VStack {
                MapView(region: $manager.region, selectedSegmentID: $manager.selectedSegmentID, segments: manager.roadSegments) // Live segments
                    .ignoresSafeArea()
                    .overlay(alignment: .top) {
                        ActivityView(manager: manager)
                    }
                    .overlay(alignment: .bottom) {
                        // Display summary only when not tracking
                        SummaryView(manager: manager)
                    }
                VStack {
                    Toggle(isOn: $manager.autoTrackingEnabled) {
                        Text("Auto-Track Driving")
                    }
                    .padding(.horizontal)
                    
                    Button(action: {
                        if manager.isTracking {
                            // If tracking, always allow stopping
                            manager.stopTracking()
                        } else {
                            // If not tracking, proceed with permission checks and start
                            if manager.authorizationStatus == .notDetermined || manager.motionAuthorizationStatus == .notDetermined {
                                showingPermissionAlert = true
                            } else if manager.authorizationStatus == .denied || manager.motionAuthorizationStatus == .denied {
                                showingPermissionAlert = true // User denied previously
                            } else {
                                manager.startTracking()
                            }
                        }
                    }) {
                        Text(manager.isTracking ? "Stop Tracking" : "Start Tracking")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(manager.isTracking ? Color.red : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(15)
                    }
                    // The START button is disabled ONLY if the app is ALREADY tracking AND auto-tracking is enabled.
                    // The STOP button (when manager.isTracking is true) is always enabled.
                    .disabled(!manager.isTracking && manager.autoTrackingEnabled)
                }
                .padding()
            }
            .navigationTitle("Pothole Detector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: TrackHistoryView(manager: manager)) {
                        Text("History")
                    }
                }
            }
        }
        .onAppear {
            manager.requestPermissions()
        }
        .alert("Permissions Required", isPresented: $showingPermissionAlert) {
            Button("OK") {
                // Direct user to settings if permissions are denied
                if manager.authorizationStatus == .denied || manager.motionAuthorizationStatus == .denied {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } else {
                    manager.requestPermissions() // Try requesting again if not determined
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

