//
//  SettingsScreen.swift
//  Journal
//

import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

struct SettingsScreen: View {
    @State private var automation = AutomationCoordinator.shared

    var body: some View {
        Form {
            AutomationSettingsSection(model: automation)
            DataTransferSettingsSection()
        }
        .navigationTitle("Settings")
        .scrollDismissesKeyboard(.interactively)
        .task {
            automation.refreshPermissionStates()
        }
    }
}

private struct DataTransferSettingsSection: View {
    @Environment(\.modelContext) private var modelContext
    @State private var exportDocument: JournalArchiveDocument?
    @State private var isExportPresented = false
    @State private var isImportPresented = false
    @State private var pendingImport: JournalDataArchive?
    @State private var isImportConfirmationPresented = false
    @State private var notice: DataTransferNotice?

    var body: some View {
        Section {
            Button {
                prepareExport()
            } label: {
                Label("Export All Data", systemImage: "square.and.arrow.up")
            }

            Button {
                isImportPresented = true
            } label: {
                Label("Import Data", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Data")
        } footer: {
            Text(
                "Export creates a JSON backup of all Journal data. Import replaces all current Journal data with the selected backup."
            )
        }
        .fileExporter(
            isPresented: $isExportPresented,
            document: exportDocument,
            contentType: .json,
            defaultFilename: defaultExportFilename
        ) { result in
            exportDocument = nil
            if case .failure(let error) = result {
                presentErrorUnlessCancelled(error)
            }
        }
        .fileImporter(
            isPresented: $isImportPresented,
            allowedContentTypes: [.json]
        ) { result in
            prepareImport(from: result)
        }
        .alert(
            "Replace All Journal Data?",
            isPresented: $isImportConfirmationPresented
        ) {
            Button("Cancel", role: .cancel) {
                pendingImport = nil
            }
            Button("Replace All Data", role: .destructive) {
                performImport()
            }
        } message: {
            Text(
                "This deletes the current Journal data and replaces it with the selected backup. This cannot be undone."
            )
        }
        .alert(item: $notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var defaultExportFilename: String {
        let day = Date.now.formatted(
            .iso8601.year().month().day().dateSeparator(.dash)
        )
        return "Journal Backup \(day)"
    }

    private func prepareExport() {
        do {
            exportDocument = JournalArchiveDocument(
                data: try JournalDataArchiveService.exportData(
                    from: modelContext
                )
            )
            isExportPresented = true
        } catch {
            notice = .error(error.localizedDescription)
        }
    }

    private func prepareImport(from result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            pendingImport = try JournalDataArchiveService.decode(
                Data(contentsOf: url)
            )
            DispatchQueue.main.async {
                isImportConfirmationPresented = true
            }
        } catch {
            presentErrorUnlessCancelled(error)
        }
    }

    private func performImport() {
        guard let pendingImport else { return }
        self.pendingImport = nil
        do {
            try JournalDataArchiveService.replaceAllData(
                with: pendingImport,
                in: modelContext
            )
            notice = .success
        } catch {
            notice = .error(error.localizedDescription)
        }
    }

    private func presentErrorUnlessCancelled(_ error: Error) {
        if error is CancellationError { return }
        let cocoaError = error as NSError
        guard cocoaError.domain != NSCocoaErrorDomain
                || cocoaError.code != CocoaError.userCancelled.rawValue else {
            return
        }
        notice = .error(error.localizedDescription)
    }
}

private enum DataTransferNotice: Identifiable {
    case success
    case error(String)

    var id: String {
        switch self {
        case .success: "success"
        case .error(let message): "error-\(message)"
        }
    }

    var title: String {
        switch self {
        case .success: String(localized: "Import Complete")
        case .error: String(localized: "Data Transfer Failed")
        }
    }

    var message: String {
        switch self {
        case .success:
            String(localized: "The Journal backup was imported.")
        case .error(let message):
            message
        }
    }
}

private struct AutomationSettingsSection: View {
    @Environment(\.openURL) private var openURL
    let model: AutomationCoordinator

    var body: some View {
        Section {
            AutomationPermissionRow(
                title: "Photos",
                state: model.photoPermission
            )
            AutomationPermissionRow(
                title: "Motion & Fitness",
                state: model.motionPermission
            )
            AutomationPermissionRow(
                title: "Background Location",
                state: model.locationPermission
            )

            if needsSettingsRecovery {
                Button("Open System Settings") {
                    guard let url = URL(
                        string: UIApplication.openSettingsURLString
                    ) else { return }
                    openURL(url)
                }
            }
        } header: {
            Text("Automation")
        } footer: {
            Text(
                "Journal uses these permissions to match photos and prepare detected visits and transit for review."
            )
        }
    }

    private var needsSettingsRecovery: Bool {
        [
            model.photoPermission,
            model.motionPermission,
            model.locationPermission,
        ].contains { $0 == .denied || $0 == .limited }
    }
}

private struct AutomationPermissionRow: View {
    let title: LocalizedStringResource
    let state: AutomationPermissionState

    var body: some View {
        LabeledContent {
            Text(state.title)
                .foregroundStyle(state == .allowed ? .green : .secondary)
        } label: {
            Text(title)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsScreen()
    }
}
