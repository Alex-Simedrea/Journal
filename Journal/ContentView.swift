import SwiftData
import SwiftUI

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(
                    for: [
                        LogEntry.self,
                        Person.self,
                        Place.self,
                        TransitDetails.self,
                        PlaceVisitDetails.self,
                        WorkoutDetails.self,
                        TransitType.self,
                    ]
                )
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var boardingPassImports = BoardingPassImportCoordinator()
    @State private var workoutImports = WorkoutImportCoordinator()

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                HomeScreen()
                    .commonToolbar(title: "Home")
            }
            Tab("Library", systemImage: "square.stack") {
                LibraryScreen()
                    .commonToolbar(title: "Library")
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsScreen()
            }
        }
        .task {
            _ = try? await ContactPersonSyncService
                .synchronizeAllContacts(in: modelContext)
            await workoutImports.start(in: modelContext)
            await EntryWeatherService.populateMissing(in: modelContext)
            boardingPassImports.loadNextIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                boardingPassImports.loadNextIfNeeded()
                Task {
                    await workoutImports.synchronize(in: modelContext)
                    await EntryWeatherService.populateMissing(
                        in: modelContext
                    )
                }
            }
        }
        .onOpenURL { url in
            guard BoardingPassImportDeepLink.matches(url) else { return }

            boardingPassImports.loadNextIfNeeded()
        }
        .sheet(item: $boardingPassImports.pendingImport) { pendingImport in
            BoardingPassImportReviewSheet(
                pendingImport: pendingImport,
                onComplete: boardingPassImports.complete,
                onCancel: boardingPassImports.discard
            )
        }
        .alert(
            "Couldn’t Load Boarding Pass",
            isPresented: Binding(
                get: { boardingPassImports.errorMessage != nil },
                set: { if !$0 { boardingPassImports.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                boardingPassImports.errorMessage
                    ?? "An unknown error occurred."
            )
        }
        .alert(
            "Couldn’t Sync Workouts",
            isPresented: Binding(
                get: { workoutImports.errorMessage != nil },
                set: { if !$0 { workoutImports.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                workoutImports.errorMessage
                    ?? "An unknown error occurred."
            )
        }
    }
}

#Preview {
    ContentView()
}
