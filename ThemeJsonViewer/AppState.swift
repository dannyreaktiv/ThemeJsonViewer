import Foundation
import SwiftUI

// MARK: - Models

struct SkipFolderRule: Identifiable, Codable, Equatable {
    var id: UUID
    var folderName: String

    init(id: UUID = UUID(), folderName: String) {
        self.id = id
        self.folderName = folderName
    }
}

// MARK: - AppState

@MainActor
class AppState: ObservableObject {
    @Published var sites: [ThemeSite] = []
    @Published var selectedSite: ThemeSite?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var rootDirectory: URL?
    @Published var scanStatus: String = ""
    @Published var themeCount: Int = 0
    @Published var skipFolders: [SkipFolderRule]

    // Per-theme base pixel size, keyed by ThemeSite.id string
    @Published var themeBasePx: [String: Double] = [:]

    @AppStorage("useHumanReadableThemeName") var useHumanReadableName: Bool = true

    init() {
        skipFolders = [
            SkipFolderRule(folderName: "public"),
            SkipFolderRule(folderName: "app"),
            SkipFolderRule(folderName: "www"),
            SkipFolderRule(folderName: "htdocs"),
            SkipFolderRule(folderName: "html"),
            SkipFolderRule(folderName: "web"),
            SkipFolderRule(folderName: "webroot"),
        ]
    }

    func basePx(for site: ThemeSite) -> Double {
        themeBasePx[site.id.uuidString] ?? 16.0
    }

    func setBasePx(_ px: Double, for site: ThemeSite) {
        themeBasePx[site.id.uuidString] = px
    }

    // MARK: - Directory

    func openDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose your WordPress root directory or a parent folder containing multiple sites"
        panel.prompt = "Open"
        if panel.runModal() == .OK, let url = panel.url {
            loadThemes(from: url)
        }
    }

    // MARK: - Load themes

    func loadThemes(from rootURL: URL) {
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
            self.rootDirectory = rootURL
            self.sites = []
            self.selectedSite = nil
            self.themeCount = 0
            self.scanStatus = "Scanning…"
        }

        let skipList = skipFolders.map { $0.folderName.lowercased() }

        Task.detached(priority: .userInitiated) { [self] in
            let urls = self.findThemeJsonFiles(in: rootURL) { status in
                Task { @MainActor in self.scanStatus = status }
            }

            for url in urls {
                if let site = self.parseSite(themeJsonURL: url, rootURL: rootURL, skipList: skipList) {
                    await MainActor.run {
                        let key = (site.parentFolder.lowercased(), site.siteName.lowercased())
                        let idx = self.sites.firstIndex {
                            ($0.parentFolder.lowercased(), $0.siteName.lowercased()) > key
                        } ?? self.sites.endIndex
                        self.sites.insert(site, at: idx)
                        self.themeCount = self.sites.count
                        self.scanStatus = "Found \(self.sites.count) theme\(self.sites.count == 1 ? "" : "s")…"
                    }
                }
            }

            await MainActor.run {
                self.isLoading = false
                self.scanStatus = ""
                if self.sites.isEmpty {
                    self.errorMessage = "No theme.json files found in the selected directory."
                }
            }
        }
    }

    // MARK: - Scanner

    private nonisolated func findThemeJsonFiles(
        in rootURL: URL,
        progress: @escaping (String) -> Void
    ) -> [URL] {
        let pruned: Set<String> = ["node_modules", "vendor", ".git", ".svn", ".hg",
                                   "dist", "build", ".cache", "bower_components"]
        var results: [URL] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var scanned = 0
        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent
            // Prune entire directories
            if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                if pruned.contains(name) {
                    enumerator.skipDescendants()
                }
                continue
            }
            scanned += 1
            if scanned % 300 == 0 { progress("Scanning… (\(scanned) files)") }
            guard name == "theme.json" else { continue }
            let parts = fileURL.pathComponents
            guard !parts.contains(where: { pruned.contains($0) }) else { continue }
            if let tIdx = parts.lastIndex(of: "themes"),
               tIdx >= 1, parts[tIdx - 1] == "wp-content",
               tIdx + 1 < parts.count {
                results.append(fileURL)
            }
        }
        return results
    }

    // MARK: - Parse a single site (synchronous — no async needed)

    private nonisolated func parseSite(
        themeJsonURL: URL,
        rootURL: URL,
        skipList: [String]
    ) -> ThemeSite? {
        let parts = themeJsonURL.pathComponents
        guard
            let tIdx = parts.lastIndex(of: "themes"),
            tIdx >= 2,
            parts[tIdx - 1] == "wp-content"
        else { return nil }

        let wpIdx = tIdx - 1
        let themeSlug = parts[tIdx + 1]

        let parentFolder = resolveProjectName(
            components: parts,
            wpContentIdx: wpIdx,
            skipList: skipList
        )

        let themeDir = themeJsonURL.deletingLastPathComponent()
        let styleCSSURL = themeDir.appendingPathComponent("style.css")
        let displayName = parseThemeName(from: styleCSSURL) ?? themeSlug

        guard let rawData = try? Data(contentsOf: themeJsonURL) else { return nil }
        let rawString = String(data: rawData, encoding: .utf8) ?? ""

        var schemaURL: URL? = nil
        if let top = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any],
           let schemaStr = top["$schema"] as? String {
            schemaURL = URL(string: schemaStr)
        }

        let cssVars: [CSSVariable]
        do {
            let themeJSON = try JSONDecoder().decode(ThemeJSON.self, from: rawData)
            cssVars = WordPressCSSGenerator.generateVariables(from: themeJSON)
        } catch {
            cssVars = []
        }

        return ThemeSite(
            parentFolder: parentFolder,
            siteName: themeSlug,
            themeDisplayName: displayName,
            themeJsonURL: themeJsonURL,
            styleCssURL: FileManager.default.fileExists(atPath: styleCSSURL.path) ? styleCSSURL : nil,
            rawThemeJSON: rawString,
            schemaURL: schemaURL,
            cssVariables: cssVars
        )
    }

    // MARK: - Project name: walk-up skip list

    private nonisolated func resolveProjectName(
        components: [String],
        wpContentIdx: Int,
        skipList: [String]
    ) -> String {
        var cursor = wpContentIdx - 1
        while cursor >= 0 {
            let folder = components[cursor]
            if folder.isEmpty || folder == "/" { break }
            if !skipList.contains(folder.lowercased()) {
                return folder
            }
            cursor -= 1
        }
        return wpContentIdx >= 1 ? components[wpContentIdx - 1] : "Unknown"
    }

    // MARK: - style.css parser

    private nonisolated func parseThemeName(from url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: .newlines).prefix(60) {
            let clean = line
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/* "))
                .trimmingCharacters(in: .whitespaces)
            if clean.lowercased().hasPrefix("theme name:") {
                let name = String(clean.dropFirst("theme name:".count))
                    .trimmingCharacters(in: .whitespaces)
                return name.isEmpty ? nil : name
            }
        }
        return nil
    }
}
