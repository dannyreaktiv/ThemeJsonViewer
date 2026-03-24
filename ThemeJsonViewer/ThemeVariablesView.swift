import SwiftUI
import AppKit

// MARK: - Value Annotation Engine

/// Produces a human-readable annotation for a CSS value, given:
///   - the raw value string
///   - the full variable map (for var() resolution)
///   - the base pixel size
struct ValueAnnotator {
    let allVars: [String: String]   // name → value (full map for this theme)
    let basePx: Double

    // MARK: - Public entry point

    func annotate(_ value: String) -> String? {
        let t = value.trimmingCharacters(in: .whitespaces)

        // 1. clamp(min, preferred, max) → "Xpx – Ypx"
        if let annotation = annotateClamp(t) { return annotation }

        // 2. var(--wp--...) → resolved value
        if let annotation = annotateVar(t) { return annotation }

        // 3. calc(…) → computed px
        if let annotation = annotateCalc(t) { return annotation }

        // 4. simple rem/em/px
        if let annotation = annotateSimple(t) { return annotation }

        return nil
    }

    // MARK: - clamp()

    private func annotateClamp(_ t: String) -> String? {
        guard t.lowercased().hasPrefix("clamp("), t.hasSuffix(")") else { return nil }
        let inner = String(t.dropFirst(6).dropLast(1))
        let args = splitArgs(inner)
        guard args.count >= 2 else { return nil }

        let minStr = args[0].trimmingCharacters(in: .whitespaces)
        let maxStr = args[args.count - 1].trimmingCharacters(in: .whitespaces)

        let minPx = toPx(minStr)
        let maxPx = toPx(maxStr)

        switch (minPx, maxPx) {
        case (.some(let mn), .some(let mx)):
            return "≈ \(fmt(mn))px – \(fmt(mx))px"
        case (.some(let mn), nil):
            return "min \(fmt(mn))px"
        case (nil, .some(let mx)):
            return "max \(fmt(mx))px"
        default:
            return nil
        }
    }

    // MARK: - var()

    private func annotateVar(_ t: String) -> String? {
        guard t.lowercased().hasPrefix("var("), t.hasSuffix(")") else { return nil }
        let inner = String(t.dropFirst(4).dropLast(1))
        let varName = inner.components(separatedBy: ",")[0]
            .trimmingCharacters(in: .whitespaces)
        guard let resolved = allVars[varName] else { return "unresolved" }
        // Recursively annotate the resolved value, or just show it truncated
        let short = resolved.count > 40 ? String(resolved.prefix(40)) + "…" : resolved
        return "→ \(short)"
    }

    // MARK: - calc()

    private func annotateCalc(_ t: String) -> String? {
        guard t.lowercased().hasPrefix("calc("), t.hasSuffix(")") else { return nil }
        let inner = String(t.dropFirst(5).dropLast(1))
        if let px = evalCalc(inner) { return "≈ \(fmt(px))px" }
        return nil
    }

    // MARK: - Simple values

    private func annotateSimple(_ t: String) -> String? {
        // Skip if it already contains no units we can convert
        if t.hasSuffix("rem") || t.hasSuffix("em") {
            if let px = toPx(t) { return "= \(fmt(px))px" }
        }
        return nil
    }

    // MARK: - Helpers

    /// Split top-level comma-separated args (not inside nested parens)
    private func splitArgs(_ s: String) -> [String] {
        var args: [String] = []
        var depth = 0
        var current = ""
        for ch in s {
            switch ch {
            case "(": depth += 1; current.append(ch)
            case ")": depth -= 1; current.append(ch)
            case "," where depth == 0:
                args.append(current)
                current = ""
            default:
                current.append(ch)
            }
        }
        if !current.isEmpty { args.append(current) }
        return args
    }

    /// Convert a CSS length string to px using basePx for rem/em
    func toPx(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasSuffix("px"),  let n = Double(t.dropLast(2))  { return n }
        if t.hasSuffix("rem"), let n = Double(t.dropLast(3))  { return n * basePx }
        if t.hasSuffix("em"),  let n = Double(t.dropLast(2))  { return n * basePx }
        if t.hasSuffix("pt"),  let n = Double(t.dropLast(2))  { return n * 1.333 }
        return nil
    }

    /// Very simple calc evaluator: handles +, -, *, / with px/rem/em operands
    private func evalCalc(_ expr: String) -> Double? {
        // Strip inner calc() wrappers
        var s = expr.trimmingCharacters(in: .whitespaces)
        if s.lowercased().hasPrefix("calc(") && s.hasSuffix(")") {
            s = String(s.dropFirst(5).dropLast(1))
        }

        // Tokenize: numbers with optional units, and operators +, -, *, /
        // Handle subtraction carefully (negative numbers)
        var tokens: [String] = []
        var current = ""
        for ch in s {
            if ch == "+" || ch == "*" || ch == "/" {
                if !current.isEmpty { tokens.append(current.trimmingCharacters(in: .whitespaces)) }
                tokens.append(String(ch))
                current = ""
            } else if ch == "-" && !current.trimmingCharacters(in: .whitespaces).isEmpty {
                tokens.append(current.trimmingCharacters(in: .whitespaces))
                tokens.append("-")
                current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current.trimmingCharacters(in: .whitespaces)) }
        tokens = tokens.filter { !$0.isEmpty && $0 != " " }

        // Evaluate left-to-right (no precedence needed for simple CSS calc)
        guard !tokens.isEmpty else { return nil }
        guard let first = tokenToPx(tokens[0]) else { return nil }
        var result = first
        var i = 1
        while i + 1 < tokens.count {
            let op = tokens[i]
            let rhs = tokens[i + 1]
            guard let rhsVal = tokenToPx(rhs) else { return nil }
            switch op {
            case "+": result += rhsVal
            case "-": result -= rhsVal
            case "*": result *= rhsVal
            case "/": guard rhsVal != 0 else { return nil }; result /= rhsVal
            default: return nil
            }
            i += 2
        }
        return result
    }

    private func tokenToPx(_ t: String) -> Double? {
        // Try as CSS length first
        if let px = toPx(t) { return px }
        // Try as bare number (unitless, treat as px or multiplier)
        return Double(t)
    }

    private func fmt(_ n: Double) -> String {
        if n == n.rounded() { return String(Int(n.rounded())) }
        return String(format: "%.1f", n)
    }
}

// MARK: - ThemeVariablesView

struct ThemeVariablesView: View {
    let site: ThemeSite
    let useHumanReadableName: Bool
    let appState: AppState   // for basePx read/write

    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\CSSVariable.name)]
    @State private var copiedID: UUID?
    @State private var filterCategory: String = "All"
    @State private var basePxInput: String = ""

    // Build a lookup map for cross-referencing var()
    private var varMap: [String: String] {
        Dictionary(uniqueKeysWithValues: site.cssVariables.map { ($0.name, $0.value) })
    }

    private var currentBasePx: Double { appState.basePx(for: site) }

    private var annotator: ValueAnnotator {
        ValueAnnotator(allVars: varMap, basePx: currentBasePx)
    }

    var categories: [String] {
        var seen = Set<String>()
        var order: [String] = ["All"]
        for v in site.cssVariables {
            let c = categoryLabel(for: v.name)
            if seen.insert(c).inserted { order.append(c) }
        }
        return order
    }

    var filteredVariables: [CSSVariable] {
        site.cssVariables.filter { v in
            let matchSearch = searchText.isEmpty
                || v.name.localizedCaseInsensitiveContains(searchText)
                || v.value.localizedCaseInsensitiveContains(searchText)
            let matchCat = filterCategory == "All" || categoryLabel(for: v.name) == filterCategory
            return matchSearch && matchCat
        }
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ──────────────────────────────────────────────────────
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(useHumanReadableName ? site.themeDisplayName : site.siteName)
                        .font(.title2).fontWeight(.semibold)
                    if useHumanReadableName && site.themeDisplayName != site.siteName {
                        Text(site.siteName)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Text(site.themeJsonURL.path)
                        .font(.caption).foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.middle)
                }

                Spacer()

                // Base pixel control
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Base px:")
                            .font(.caption).foregroundStyle(.secondary)
                        TextField("16", text: $basePxInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 52)
                            .font(.system(.caption, design: .monospaced))
                            .onSubmit { commitBasePx() }
                            .onChange(of: basePxInput) { _ in commitBasePx() }
                        Text("px")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if currentBasePx != 16 {
                        Text("(default: 16px)")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(filteredVariables.count) / \(site.cssVariables.count)")
                        .font(.title3).fontWeight(.medium).monospacedDigit()
                    Text("variables")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.bar)

            Divider()

            // ── Filter bar ───────────────────────────────────────────────────
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary).font(.callout)
                    TextField("Search…", text: $searchText).textFieldStyle(.plain)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                .frame(maxWidth: 280)

                Picker("", selection: $filterCategory) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 175)

                Spacer()

                if copiedID != nil {
                    Label("Copied!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.callout)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 7)
            .animation(.easeInOut(duration: 0.2), value: copiedID)

            Divider()

            // ── Table ────────────────────────────────────────────────────────
            if site.cssVariables.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36)).foregroundStyle(.tertiary)
                    Text("No CSS variables found in this theme.json")
                        .foregroundStyle(.secondary)
                    Text("Check the Raw JSON tab to see what the file contains.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filteredVariables.sorted(using: sortOrder), sortOrder: $sortOrder) {
                    TableColumn("Variable", value: \.name) { variable in
                        CopyableCell(
                            text: variable.name,
                            annotation: nil,
                            copiedID: $copiedID,
                            variableID: variable.id,
                            showSwatch: false
                        )
                    }
                    .width(min: 220, ideal: 390)

                    TableColumn("Value", value: \.value) { variable in
                        CopyableCell(
                            text: variable.value,
                            annotation: annotator.annotate(variable.value),
                            copiedID: $copiedID,
                            variableID: variable.id,
                            showSwatch: true
                        )
                    }
                    .width(min: 160, ideal: 340)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { basePxInput = formatBasePx(currentBasePx) }
        .onChange(of: site.id) { _ in
            searchText = ""
            filterCategory = "All"
            basePxInput = formatBasePx(appState.basePx(for: site))
        }
    }

    private func commitBasePx() {
        let cleaned = basePxInput.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "px", with: "")
        if let val = Double(cleaned), val > 0, val <= 48 {
            appState.setBasePx(val, for: site)
        }
    }

    private func formatBasePx(_ px: Double) -> String {
        px == px.rounded() ? String(Int(px)) : String(format: "%.1f", px)
    }

    private func categoryLabel(for name: String) -> String {
        let parts = name.split(separator: "-").filter { !$0.isEmpty }
        guard parts.count >= 3 else { return "Other" }
        let cat = String(parts[2])
        switch cat {
        case "color":     return "🎨 Color"
        case "gradient":  return "🌈 Gradient"
        case "duotone":   return "◑ Duotone"
        case "font":
            if parts.count >= 4 {
                return parts[3] == "size" ? "🔤 Font Size" : "🔠 Font Family"
            }
            return "🔤 Typography"
        case "spacing":   return "📐 Spacing"
        case "shadow":    return "🌑 Shadow"
        case "border":    return "⬜ Border"
        case "dimension": return "📏 Dimension"
        case "custom":    return "✨ Custom"
        default:          return cat.capitalized
        }
    }
}

// MARK: - Copyable Cell

struct CopyableCell: View {
    let text: String
    let annotation: String?
    @Binding var copiedID: UUID?
    let variableID: UUID
    var showSwatch: Bool = false

    @State private var isHovered = false
    private var isCopied: Bool { copiedID == variableID }

    var body: some View {
        HStack(spacing: 6) {
            // Color swatch
            if showSwatch, let color = extractColor(from: text) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: 14, height: 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
            }

            // Main value text
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)

            // Annotation (px range, resolved var, calc result, rem→px)
            if let ann = annotation {
                Text(ann)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .opacity(0.75)
                    .lineLimit(1)
            }

            Spacer()

            if isHovered && !isCopied {
                Image(systemName: "doc.on.doc")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .background(
            isCopied
                ? Color.accentColor.opacity(0.15)
                : isHovered ? Color.primary.opacity(0.04) : Color.clear,
            in: RoundedRectangle(cornerRadius: 4)
        )
        .onHover { isHovered = $0 }
        .onTapGesture { copyText() }
        .help("Click to copy: \(text)")
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation(.spring(duration: 0.2)) { copiedID = variableID }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { if copiedID == variableID { copiedID = nil } }
        }
    }

    private func extractColor(from value: String) -> Color? {
        let t = value.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") {
            let hex = String(t.dropFirst())
            if hex.count == 6 || hex.count == 8 {
                var int: UInt64 = 0
                guard Scanner(string: hex).scanHexInt64(&int) else { return nil }
                if hex.count == 6 {
                    return Color(red: Double((int >> 16) & 0xFF) / 255,
                                 green: Double((int >> 8) & 0xFF) / 255,
                                 blue: Double(int & 0xFF) / 255)
                } else {
                    return Color(red: Double((int >> 16) & 0xFF) / 255,
                                 green: Double((int >> 8) & 0xFF) / 255,
                                 blue: Double(int & 0xFF) / 255,
                                 opacity: Double((int >> 24) & 0xFF) / 255)
                }
            }
        }
        let named: [String: Color] = [
            "white": .white, "black": .black, "red": .red, "blue": .blue,
            "green": .green, "yellow": .yellow, "gray": .gray, "grey": .gray,
            "orange": .orange, "purple": .purple, "pink": .pink, "cyan": .cyan
        ]
        return named[t.lowercased()]
    }
}
