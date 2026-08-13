//
//  TrackHistoryView.swift
//  RoadSmoothness
//
//  Created by Jay Desai on 26/01/26.
//

import SwiftUI
import MapKit

struct SavedTracksView: View {
    let track: Track

    var body: some View {
        VStack(alignment: .leading) {
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
        }
        .padding(.vertical, 5)
    }
}
// MARK: - TrackHistoryView (New View)
struct TrackHistoryView: View {
    @State var manager: LocationAndMotionManager
    @State private var selectedTracks = Set<UUID>()
    @State private var isShowingDeleteConfirmation: Bool = false
    @Environment(\.editMode) private var editMode

    var body: some View {
        List(selection: $selectedTracks) {
            if manager.savedTracks.isEmpty {
                Text("No tracks saved yet. Start a ride!")
                    .foregroundColor(.gray)
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

// MARK: - TrackDetailView (New View)
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
        VStack {
            MapView(region: $region, selectedSegmentID: $selectedSegmentID, segments: track.segments, showsUserLocation: false) // Show historical segments, no live user dot
            
            VStack(alignment: .leading) {
                Text("Ride Details")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.bottom, 5)

                Text("Date: \(track.date, style: .date)")
                Text("Time: \(track.date, style: .time)")
                Text("Distance: \(track.distance / 1000, specifier: "%.2f") km")
                HStack {
                    Text("Average Bumpiness:")
                    Text("\(track.avgBumpiness, specifier: "%.4f")")
                        .foregroundColor(track.avgBumpiness.bumpinessColor())
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(10)
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
            latitudeDelta: (maxLat - minLat) * 1.2, // Add some padding
            longitudeDelta: (maxLon - minLon) * 1.2
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

