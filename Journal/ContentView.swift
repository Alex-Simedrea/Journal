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
            let automationContext = backgroundContext()
            let contactContext = backgroundContext()
            let workoutContext = backgroundContext()
            let enrichmentContext = backgroundContext()
            await automation.start(in: automationContext)
            _ = try? await ContactPersonSyncService
                .synchronizeAllContacts(in: contactContext)
            await workoutImports.start(in: workoutContext)
            await EntryWeatherService.populateMissing(in: enrichmentContext)
            await TransitDistanceService.populateMissing(in: enrichmentContext)
            await LocationGeographyService.populateMissing(in: enrichmentContext)
            contentRevision &+= 1
            boardingPassImports.loadNextIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                JournalRecordingCoordinator.shared.appDidBecomeActive()
                boardingPassImports.loadNextIfNeeded()
                Task {
                    let automationContext = backgroundContext()
                    let workoutContext = backgroundContext()
                    let enrichmentContext = backgroundContext()
                    await automation.synchronize(in: automationContext)
                    await workoutImports.synchronize(in: workoutContext)
                    await EntryWeatherService.populateMissing(
                        in: enrichmentContext
                    )
                    await TransitDistanceService.populateMissing(
                        in: enrichmentContext
                    )
                    await LocationGeographyService.populateMissing(
                        in: enrichmentContext
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

    private func backgroundContext() -> ModelContext {
        let context = ModelContext(modelContext.container)
        context.autosaveEnabled = false
        return context
    }
}

#Preview {
    ContentView()
}
