import MapKit
import SwiftData
import SwiftUI

struct WorkoutRouteSection: View {
    let workoutUUID: UUID
    let model: WorkoutRouteModel

    var body: some View {
        Section("Route") {
            WorkoutRouteContent(
                state: model.state,
                points: model.points,
                onRetry: {
                    Task { await model.load(workoutUUID: workoutUUID) }
                }
            )
        }
        .task(id: workoutUUID) {
            await model.load(workoutUUID: workoutUUID)
        }
    }
}

struct WorkoutRouteContent: View {
    let state: WorkoutRouteLoadState
    let points: [WorkoutCoordinateSnapshot]
    let onRetry: () -> Void

    var body: some View {
        VStack {
            switch state {
            case .idle, .loading:
                ProgressView("Loading route…")
                    .frame(maxWidth: .infinity, minHeight: 180)
            case .loaded:
                WorkoutRouteMap(points: points)
            case .authorizationRequired:
                ContentUnavailableView {
                    Label("Health Access Required", systemImage: "heart.slash")
                } description: {
                    Text("Allow Journal to read workout routes in Health settings, then try again.")
                } actions: {
                    Button("Try Again", action: onRetry)
                }
                .frame(minHeight: 180)
            case .unavailable:
                ContentUnavailableView {
                    Label("Route Unavailable", systemImage: "map")
                } description: {
                    Text("Health does not currently provide a route for this workout.")
                }
                .frame(minHeight: 180)
            case .failed(let message):
                WorkoutRouteFailure(message: message, onRetry: onRetry)
            }
        }
    }
}

struct WorkoutRouteMap: View {
    let points: [WorkoutCoordinateSnapshot]

    var body: some View {
        Map(initialPosition: .automatic) {
            MapPolyline(coordinates: points.map(\.coordinate))
                .stroke(.blue.gradient, lineWidth: 5)

            if let origin = points.first {
                Marker(
                    "Origin",
                    systemImage: "circle.fill",
                    coordinate: origin.coordinate
                )
                .tint(.blue)
            }

            if let destination = points.last {
                Marker(
                    "Destination",
                    systemImage: "flag.fill",
                    coordinate: destination.coordinate
                )
                .tint(.red)
            }
        }
        .frame(height: 280)
        .clipShape(.rect(cornerRadius: 12))
    }
}

struct WorkoutRouteFailure: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            Button("Retry", action: onRetry)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}
