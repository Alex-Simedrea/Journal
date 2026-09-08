import SwiftData
import SwiftUI

@main struct MyApp: App {
    @UIApplicationDelegateAdaptor(JournalAppDelegate.self)
    private var appDelegate

    var body: some Scene {
        WindowGroup {
            switch JournalModelContainer.result {
            case .success(let container):
                ContentView().modelContainer(container)
            case .failure(let error):
                ContentUnavailableView {
                    Label("Couldn’t Open Journal", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("Your saved data has not been reset. Journal could not open it.")
                    Text(error.localizedDescription)
                        .font(.footnote)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

struct ContentView: View {
    var body: some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-home-zoom-gallery") {
            HomeFeedZoomGallery()
        } else if ProcessInfo.processInfo.arguments.contains("-period-summary-gallery") {
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
    @State private var isInitialFeedReady = false
    @State private var hasStartedBackgroundServices = false

    var body: some View {
        HomeScreen(
            contentRevision: contentRevision,
            onInitialFeedReady: { isInitialFeedReady = true }
        )
        .task(id: isInitialFeedReady) {
            guard isInitialFeedReady else { return }
            // The first feed interaction is more important than launch-time
            // enrichment. Give SwiftUI a quiet window to finish layout and
            // handle input before these best-effort synchronizations begin.
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            hasStartedBackgroundServices = true
            let maintenance = await JournalPersistenceServices.shared.maintenance(
                for: modelContext.container
            )
            await automation.start(using: maintenance)
            async let backgroundMaintenance: Void = runBackgroundMaintenance(
                maintenance
            )
            _ = try? await ContactPersonSyncService
                .synchronizeAllContacts(in: modelContext)
            await workoutImports.start(modelContainer: modelContext.container)
            await backgroundMaintenance
            contentRevision &+= 1
            boardingPassImports.loadNextIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                JournalRecordingCoordinator.shared.appDidBecomeActive()
                boardingPassImports.loadNextIfNeeded()
                guard isInitialFeedReady,
                      hasStartedBackgroundServices else { return }
                Task {
                    let maintenance = await JournalPersistenceServices.shared
                        .maintenance(
                            for: modelContext.container
                        )
                    await automation.synchronize(using: maintenance)
                    async let backgroundMaintenance: Void =
                        runBackgroundMaintenance(maintenance)
                    await workoutImports.synchronize(
                        modelContainer: modelContext.container
                    )
                    await backgroundMaintenance
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

    private func runBackgroundMaintenance(
        _ maintenance: JournalBackgroundMaintenance
    ) async {
        await maintenance.populateEntryEnrichment()
    }
}

#Preview {
    ContentView()
}
