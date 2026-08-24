import SwiftData
import SwiftUI

@main struct MyApp: App {
    @UIApplicationDelegateAdaptor(JournalAppDelegate.self)
    private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(JournalModelContainer.shared)
        }
    }
}

struct ContentView: View {
    var body: some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-period-summary-gallery") {
            PeriodSummaryDesignGallery()
        } else if ProcessInfo.processInfo.arguments.contains("-day-summary-gallery")
            || ProcessInfo.processInfo.environment["DAY_SUMMARY_GALLERY"] == "1" {
            DaySummaryDesignGallery()
        } else {
            JournalApplicationContent()
        }
#else
        JournalApplicationContent()
#endif
    }
}

private struct JournalApplicationContent: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var boardingPassImports = BoardingPassImportCoordinator()
    @State private var workoutImports = WorkoutImportCoordinator()
    @State private var automation = AutomationCoordinator.shared
    @State private var contentRevision = 0

    var body: some View {
        HomeScreen(contentRevision: contentRevision)
        .task {
            await automation.start(in: modelContext)
            _ = try? await ContactPersonSyncService
                .synchronizeAllContacts(in: modelContext)
            await workoutImports.start(in: modelContext)
            await EntryWeatherService.populateMissing(in: modelContext)
            await TransitDistanceService.populateMissing(in: modelContext)
            await LocationGeographyService.populateMissing(in: modelContext)
            contentRevision &+= 1
            boardingPassImports.loadNextIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                boardingPassImports.loadNextIfNeeded()
                Task {
                    await automation.synchronize(in: modelContext)
                    await workoutImports.synchronize(in: modelContext)
                    await EntryWeatherService.populateMissing(
                        in: modelContext
                    )
                    await TransitDistanceService.populateMissing(
                        in: modelContext
                    )
                    await LocationGeographyService.populateMissing(
                        in: modelContext
                    )
                    contentRevision &+= 1
                }
            } else {
                automation.pauseLiveUpdates()
            }
        }
        .onOpenURL { url in
            guard BoardingPassImportDeepLink.matches(url) else { return }

            boardingPassImports.loadNextIfNeeded()
        }
        .sheet(item: $boardingPassImports.pendingImport) { pendingImport in
            BoardingPassImportReviewSheet(
                pendingImport: pendingImport,
                onComplete: {
                    boardingPassImports.complete($0)
                    contentRevision &+= 1
                },
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
            "Couldn’t Sync Health Data",
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
