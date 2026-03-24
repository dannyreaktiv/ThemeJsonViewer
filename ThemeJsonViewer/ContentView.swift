import SwiftUI

// Notification.Name.openDirectory is declared in ThemeJsonViewerApp.swift

struct ContentView: View {
    @StateObject private var appState = AppState()
    @State private var searchText = ""
    @State private var showSettings = false

    var filteredSites: [ThemeSite] {
        guard !searchText.isEmpty else { return appState.sites }
        let q = searchText.lowercased()
        return appState.sites.filter {
            $0.siteName.lowercased().contains(q) ||
            $0.themeDisplayName.lowercased().contains(q) ||
            $0.parentFolder.lowercased().contains(q)
        }
    }

    var grouped: [(folder: String, sites: [ThemeSite])] {
        var order: [String] = []
        var dict: [String: [ThemeSite]] = [:]
        for site in filteredSites {
            if dict[site.parentFolder] == nil {
                order.append(site.parentFolder)
                dict[site.parentFolder] = []
            }
            dict[site.parentFolder]!.append(site)
        }
        return order.map { (folder: $0, sites: dict[$0]!) }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                grouped: grouped,
                selectedSite: $appState.selectedSite,
                searchText: $searchText,
                isLoading: appState.isLoading,
                scanStatus: appState.scanStatus,
                themeCount: appState.themeCount,
                useHumanReadableName: appState.useHumanReadableName,
                hasDirectory: appState.rootDirectory != nil,
                onOpenDirectory: { appState.openDirectory() }
            )
            .toolbar {
                // Only settings gear — no Open Directory button
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Settings")
                }
            }
        } detail: {
            if let site = appState.selectedSite {
                ThemeDetailView(site: site, appState: appState)
            } else {
                EmptyStateView(
                    hasDirectory: appState.rootDirectory != nil,
                    errorMessage: appState.errorMessage,
                    isLoading: appState.isLoading,
                    scanStatus: appState.scanStatus,
                    onOpen: { appState.openDirectory() }
                )
            }
        }
        .navigationTitle("WP Theme Variables")
        .onReceive(NotificationCenter.default.publisher(for: .openDirectory)) { _ in
            DispatchQueue.main.async { appState.openDirectory() }
        }
        .frame(minWidth: 920, minHeight: 540)
        .sheet(isPresented: $showSettings) {
            SettingsView(appState: appState)
        }
    }
}

// MARK: - Detail wrapper (Variables tab + Raw JSON tab)

struct ThemeDetailView: View {
    let site: ThemeSite
    @ObservedObject var appState: AppState
    @State private var selectedTab: DetailTab = .variables

    enum DetailTab: String, CaseIterable, Identifiable {
        case variables = "Variables"
        case rawJSON   = "Raw JSON"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Picker("Tab", selection: $selectedTab) {
                    ForEach(DetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 6)

                Spacer()

                if let schemaURL = site.schemaURL {
                    Link(destination: schemaURL) {
                        Label(schemaURL.lastPathComponent, systemImage: "link")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 14)
                    .help("Schema: \(schemaURL.absoluteString)")
                }
            }

            Divider()

            switch selectedTab {
            case .variables:
                ThemeVariablesView(
                    site: site,
                    useHumanReadableName: appState.useHumanReadableName,
                    appState: appState
                )
            case .rawJSON:
                RawJSONView(site: site)
            }
        }
    }
}

// MARK: - Raw JSON pane

struct RawJSONView: View {
    let site: ThemeSite
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(site.themeJsonURL.path)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                if copied {
                    Label("Copied", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(site.rawThemeJSON, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label("Copy JSON", systemImage: "doc.on.doc").font(.caption)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)

            Divider()

            ScrollView([.horizontal, .vertical]) {
                Text(site.rawThemeJSON)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(14)
            }
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    let grouped: [(folder: String, sites: [ThemeSite])]
    @Binding var selectedSite: ThemeSite?
    @Binding var searchText: String
    let isLoading: Bool
    let scanStatus: String
    let themeCount: Int
    let useHumanReadableName: Bool
    let hasDirectory: Bool
    let onOpenDirectory: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Scan progress banner
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(scanStatus.isEmpty ? "Scanning…" : scanStatus).font(.caption)
                        if themeCount > 0 {
                            Text("\(themeCount) found so far")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                Divider()
            }

            if grouped.isEmpty && !isLoading {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 36)).foregroundStyle(.tertiary)
                    Text(hasDirectory ? "No themes found" : "No directory opened")
                        .foregroundStyle(.secondary).font(.callout)
                    // Show Open Directory here only when there are no sites
                    Button("Open Directory…", action: onOpenDirectory)
                        .keyboardShortcut("o", modifiers: .command)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedSite) {
                    ForEach(grouped, id: \.folder) { group in
                        Section(group.folder) {
                            ForEach(group.sites) { site in
                                SidebarRow(site: site, useHumanReadableName: useHumanReadableName)
                                    .tag(site)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Filter themes")
        .navigationSplitViewColumnWidth(min: 210, ideal: 255)
    }
}

struct SidebarRow: View {
    let site: ThemeSite
    let useHumanReadableName: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(useHumanReadableName ? site.themeDisplayName : site.siteName)
                .font(.callout).lineLimit(2)
            HStack(spacing: 4) {
                if useHumanReadableName && site.themeDisplayName != site.siteName {
                    Text(site.siteName)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text("\(site.cssVariables.count) vars")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Empty State (detail panel)

struct EmptyStateView: View {
    let hasDirectory: Bool
    let errorMessage: String?
    let isLoading: Bool
    let scanStatus: String
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 52)).foregroundStyle(.tertiary)
            if isLoading {
                ProgressView()
                Text(scanStatus.isEmpty ? "Scanning…" : scanStatus).foregroundStyle(.secondary)
            } else if let error = errorMessage {
                Text(error).foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else if !hasDirectory {
                Text("Open a directory from the sidebar").foregroundStyle(.secondary)
            } else {
                Text("Select a theme from the sidebar").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Settings Sheet

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var newFolderName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.title2).fontWeight(.semibold)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.return)
            }
            .padding()
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Open directory
                    GroupBox("Directory") {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                if let dir = appState.rootDirectory {
                                    Text(dir.path)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2).truncationMode(.middle)
                                } else {
                                    Text("No directory selected")
                                        .font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            Button("Open…") {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    appState.openDirectory()
                                }
                            }
                        }
                        .padding(8)
                    }

                    // Display
                    GroupBox("Display") {
                        Toggle(isOn: $appState.useHumanReadableName) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Use human-readable theme name")
                                Text("Reads \"Theme Name:\" from style.css instead of the directory slug")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                    }

                    // Skip folders
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("When resolving a project name the app walks up the directory tree from /wp-content/. Any folder in this list is skipped — the first non-skipped ancestor becomes the project name.")
                                .font(.caption).foregroundStyle(.secondary)

                            ForEach($appState.skipFolders) { $rule in
                                HStack {
                                    Image(systemName: "arrow.up.to.line")
                                        .foregroundStyle(.secondary).font(.caption2)
                                    Text(rule.folderName)
                                        .font(.system(.callout, design: .monospaced))
                                    Spacer()
                                    Button(role: .destructive) {
                                        appState.skipFolders.removeAll { $0.id == rule.id }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red.opacity(0.75))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 3).padding(.horizontal, 6)
                                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 5))
                            }
                            .onMove { from, to in appState.skipFolders.move(fromOffsets: from, toOffset: to) }

                            HStack(spacing: 8) {
                                TextField("Folder name to skip…", text: $newFolderName)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit { addSkipFolder() }
                                Button("Add", action: addSkipFolder)
                                    .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
                            }

                            Button("Reset to defaults") {
                                appState.skipFolders = [
                                    SkipFolderRule(folderName: "public"),
                                    SkipFolderRule(folderName: "app"),
                                    SkipFolderRule(folderName: "www"),
                                    SkipFolderRule(folderName: "htdocs"),
                                    SkipFolderRule(folderName: "html"),
                                    SkipFolderRule(folderName: "web"),
                                    SkipFolderRule(folderName: "webroot"),
                                ]
                            }
                            .foregroundStyle(.secondary).font(.caption)
                        }
                        .padding(8)
                    } label: {
                        Text("Project Name: Skip Folders").font(.headline)
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 560)
    }

    private func addSkipFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty else { return }
        appState.skipFolders.append(SkipFolderRule(folderName: name))
        newFolderName = ""
    }
}
