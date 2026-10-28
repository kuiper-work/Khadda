//
//  TrackHistoryView.swift
//  RoadSmoothness
//
//  Created by Jay Desai on 26/01/26.
//

import SwiftUI
import MapKit

// MARK: - SavedTracksView
struct SavedTracksView: View {
    let track: Track

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(track.date, style: .date)
                .font(.headline)
            Text(track.date, style: .time)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                Text("Distance: \(track.distance / 1000, specifier: "%.2f") km")
                Spacer()
                Text("Avg Bumpiness: \(track.avgBumpiness, specifier: "%.4f")")
                    .foregroundColor(track.avgBumpiness.bumpinessColor())
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - TrackHistoryView
struct TrackHistoryView: View {
    @State var manager: LocationAndMotionManager
    @State private var selectedTracks = Set<UUID>()
    @State private var isShowingDeleteConfirmation: Bool = false
    @Environment(\.editMode) private var editMode

    var body: some View {
        List(selection: $selectedTracks) {
            if manager.savedTracks.isEmpty {
                ContentUnavailableView(
                    "No Rides Recorded",
                    systemImage: "map",
                    description: Text("Start a ride to automatically track and record road bumpiness.")
                )
            } else {
                ForEach(manager.savedTracks) { track in
                    NavigationLink(destination: TrackDetailView(track: track)) {
                        SavedTracksView(track: track)
                    }
                }
                .onDelete(perform: deleteTrack) // Allow deletion
            }
        }
        .navigationTitle("Ride History")
        .onAppear {
            // Ensure tracks are loaded when view appears (in case new ones were saved)
            manager.loadSavedTracks()
        }
        .toolbar {
            if !manager.savedTracks.isEmpty {
                EditButton()

                if editMode?.wrappedValue.isEditing == true && selectedTracks.isEmpty == false {
                    Button("Delete Selected", systemImage: "trash") {
                        deleteSelected()
                    }
                }
            }
        }
    }
    
    func deleteSelected() {
        deleteTrackFiles(for: selectedTracks)
        manager.savedTracks.removeAll {
            selectedTracks.contains($0.id)
        }
    }
    
    // Made internal (default access level) so onDelete can access it
    func deleteTrack(at offsets: IndexSet) {
        // Implement deletion logic
        guard !offsets.isEmpty else { return }
        deleteTrackFiles(for: Set([manager.savedTracks[offsets.first!].id]))
        manager.savedTracks.remove(atOffsets: offsets)
    }
    
    func deleteTrackFiles(for selectedTrackIDs: Set<UUID>) {
        for selectedTrackID in selectedTrackIDs {
            do {
                let fileURL = try manager.trackFileURL(for: selectedTrackID)
                try FileManager.default.removeItem(at: fileURL)
                DispatchQueue.main.async {
                    print("Track deleted: \(selectedTrackID)")
                }
            } catch {
                print("Error deleting track file: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - TrackDetailView
struct TrackDetailView: View {
    let track: Track
    @State private var region: MKCoordinateRegion
    @State private var selectedSegmentID: UUID? = nil

    init(track: Track) {
        self.track = track
        // Calculate initial region to encompass all segments of the track
        _region = State(initialValue: TrackDetailView.defaultRegion(for: track.segments))
    }

    var body: some View {
        VStack(spacing: 0) {
            MapView(regionToDisplay: $region, selectedSegmentID: $selectedSegmentID, segments: track.segments, showsUserLocation: false)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Track Analysis")
                    .font(.title3)
                    .fontWeight(.bold)

                HStack {
                    Label(track.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Label(String(format: "%.2f km", track.distance / 1000), systemImage: "location.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                Divider()

                // Track Bumpiness Gauge (displayed exclusively when selecting a track from History)
                BumpinessGaugeView(bumpinessScore: track.avgBumpiness)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
            .padding()
        }
        // Corrected navigationTitle usage: Pass a Text view with the formatted date
        .navigationTitle(Text(track.date, format: .dateTime.month(.abbreviated).day().hour().minute()))
        .navigationBarTitleDisplayMode(.inline)
    }

    // Helper to calculate a region that fits all segments
    ///  Default region for showing the map being travelled on
    /// - Parameter segments: <#segments description#>
    /// - Returns: <#description#>
    private static func defaultRegion(for segments: [RoadSegment]) -> MKCoordinateRegion {
        guard !segments.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }

        var minLat = 90.0, maxLat = -90.0
        var minLon = 180.0, maxLon = -180.0

        for segment in segments {
            minLat = min(minLat, segment.startCoordinate.latitude, segment.endCoordinate.latitude)
            maxLat = max(maxLat, segment.startCoordinate.latitude, segment.endCoordinate.latitude)
            minLon = min(minLon, segment.startCoordinate.longitude, segment.endCoordinate.longitude)
            maxLon = max(maxLon, segment.startCoordinate.longitude, segment.endCoordinate.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.2, 0.005),
            longitudeDelta: max((maxLon - minLon) * 1.2, 0.005)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
