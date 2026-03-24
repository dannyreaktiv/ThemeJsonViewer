import Foundation

// MARK: - App Models

struct ThemeSite: Identifiable, Hashable {
    let id = UUID()
    let parentFolder: String
    let siteName: String
    var themeDisplayName: String
    let themeJsonURL: URL
    var styleCssURL: URL?
    var rawThemeJSON: String = ""       // raw file content for debug pane
    var schemaURL: URL?                 // from "$schema" key in theme.json
    var cssVariables: [CSSVariable] = []

    static func == (lhs: ThemeSite, rhs: ThemeSite) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct CSSVariable: Identifiable {
    let id = UUID()
    let name: String
    let value: String
}

// MARK: - WordPress theme.json schema models

struct ThemeJSON: Codable {
    var settings: ThemeSettings?
}

struct ThemeSettings: Codable {
    var color: ColorSettings?
    var typography: TypographySettings?
    var spacing: SpacingSettings?
    var border: BorderSettings?
    var shadow: ShadowSettings?
    var dimensions: DimensionsSettings?
    var custom: AnyCodable?
}

struct ColorSettings: Codable {
    var palette: [ColorPreset]?
    var gradients: [GradientPreset]?
    var duotone: [DuotonePreset]?
}

struct ColorPreset: Codable {
    var slug: String
    var color: String
    var name: String?
}

struct GradientPreset: Codable {
    var slug: String
    var gradient: String
    var name: String?
}

struct DuotonePreset: Codable {
    var slug: String
    var colors: [String]
    var name: String?
}

struct TypographySettings: Codable {
    var fontSizes: [FontSizePreset]?
    var fontFamilies: [FontFamilyPreset]?
    var fluid: FluidGlobalSetting?
}

enum FluidGlobalSetting: Codable {
    case bool(Bool)
    case settings(FluidGlobalParams)

    var isEnabled: Bool {
        switch self {
        case .bool(let b): return b
        case .settings: return true
        }
    }

    var params: FluidGlobalParams? {
        if case .settings(let p) = self { return p }
        return nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let p = try? c.decode(FluidGlobalParams.self) { self = .settings(p) }
        else { self = .bool(false) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .bool(let b): try c.encode(b)
        case .settings(let p): try c.encode(p)
        }
    }
}

struct FluidGlobalParams: Codable {
    var minFontSize: String?
    var maxViewportWidth: String?
    var minViewportWidth: String?
}

struct FontSizePreset: Codable {
    var slug: String
    var size: String
    var name: String?
    var fluid: FluidFontSizeSetting?
}

enum FluidFontSizeSetting: Codable {
    case disabled
    case auto
    case explicit(min: String, max: String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) {
            self = b ? .auto : .disabled
        } else if let obj = try? c.decode(FluidMinMax.self) {
            self = .explicit(min: obj.min ?? "", max: obj.max ?? "")
        } else {
            self = .auto
        }
    }

    func encode(to encoder: Encoder) throws {}
}

struct FluidMinMax: Codable {
    var min: String?
    var max: String?
}

struct FontFamilyPreset: Codable {
    var slug: String
    var fontFamily: String
    var name: String?
}

struct SpacingSettings: Codable {
    var spacingSizes: [SpacingPreset]?
    var spacingScale: SpacingScale?
}

struct SpacingPreset: Codable {
    var slug: String
    var size: String
    var name: String?
}

struct SpacingScale: Codable {
    var `operator`: String?
    var increment: Double?
    var steps: Int?
    var mediumStep: Double?
    var unit: String?
}

struct BorderSettings: Codable {
    var radiusSizes: [RadiusPreset]?
}

struct RadiusPreset: Codable {
    var slug: String
    var size: String
    var name: String?
}

struct ShadowSettings: Codable {
    var presets: [ShadowPreset]?
}

struct ShadowPreset: Codable {
    var slug: String
    var shadow: String
    var name: String?
}

struct DimensionsSettings: Codable {
    var dimensionSizes: [DimensionPreset]?
}

struct DimensionPreset: Codable {
    var slug: String
    var size: String
    var name: String?
}

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode([String: AnyCodable].self) { value = v.mapValues { $0.value } }
        else if let v = try? c.decode([AnyCodable].self) { value = v.map { $0.value } }
        else if let v = try? c.decode(String.self) { value = v }
        else if let v = try? c.decode(Int.self) { value = v }
        else if let v = try? c.decode(Double.self) { value = v }
        else if let v = try? c.decode(Bool.self) { value = v }
        else { value = "" }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let v as String: try c.encode(v)
        case let v as Int: try c.encode(v)
        case let v as Double: try c.encode(v)
        case let v as Bool: try c.encode(v)
        default: try c.encodeNil()
        }
    }
}

// MARK: - CSS Variable Generator

enum WordPressCSSGenerator {

    static func generateVariables(from themeJSON: ThemeJSON) -> [CSSVariable] {
        guard let settings = themeJSON.settings else { return [] }
        var vars: [CSSVariable] = []
        vars += colorVars(settings)
        vars += typographyVars(settings)
        vars += spacingVars(settings)
        vars += borderVars(settings)
        vars += shadowVars(settings)
        vars += dimensionVars(settings)
        vars += customVars(settings)
        return vars
    }

    private static func colorVars(_ s: ThemeSettings) -> [CSSVariable] {
        var v: [CSSVariable] = []
        guard let color = s.color else { return v }
        for p in color.palette ?? [] {
            v.append(.init(name: "--wp--preset--color--\(slug(p.slug))", value: p.color))
        }
        for p in color.gradients ?? [] {
            v.append(.init(name: "--wp--preset--gradient--\(slug(p.slug))", value: p.gradient))
        }
        for p in color.duotone ?? [] {
            v.append(.init(name: "--wp--preset--duotone--\(slug(p.slug))", value: p.colors.joined(separator: ", ")))
        }
        return v
    }

    private static func typographyVars(_ s: ThemeSettings) -> [CSSVariable] {
        var v: [CSSVariable] = []
        guard let typo = s.typography else { return v }
        let globalEnabled = typo.fluid?.isEnabled ?? false
        let globalParams = typo.fluid?.params
        for fs in typo.fontSizes ?? [] {
            let value = resolveFluidFontSize(preset: fs, globalEnabled: globalEnabled, globalParams: globalParams)
            v.append(.init(name: "--wp--preset--font-size--\(slug(fs.slug))", value: value))
        }
        for ff in typo.fontFamilies ?? [] {
            v.append(.init(name: "--wp--preset--font-family--\(slug(ff.slug))", value: ff.fontFamily))
        }
        return v
    }

    private static func resolveFluidFontSize(
        preset: FontSizePreset,
        globalEnabled: Bool,
        globalParams: FluidGlobalParams?
    ) -> String {
        if case .disabled = preset.fluid { return preset.size }
        if case .explicit(let mn, let mx) = preset.fluid, !mn.isEmpty, !mx.isEmpty {
            return computeClamp(min: mn, max: mx, globalParams: globalParams) ?? preset.size
        }
        if globalEnabled, let sizePx = toPx(preset.size) {
            let minPx = sizePx * 0.75
            return computeClamp(min: "\(formatNum(minPx))px", max: preset.size, globalParams: globalParams) ?? preset.size
        }
        return preset.size
    }

    private static func computeClamp(min: String, max: String, globalParams: FluidGlobalParams?) -> String? {
        let minVwStr = globalParams?.minViewportWidth ?? "320px"
        let maxVwStr = globalParams?.maxViewportWidth ?? "1000px"
        let minLimitStr = globalParams?.minFontSize ?? "14px"
        guard
            let minPx = toPx(min), let maxPx = toPx(max),
            let minVwPx = toPx(minVwStr), let maxVwPx = toPx(maxVwStr),
            let minLimitPx = toPx(minLimitStr),
            maxPx > minPx, minPx >= minLimitPx, (maxVwPx - minVwPx) > 0
        else { return nil }
        let vwRange = maxVwPx - minVwPx
        let slopePx = (maxPx - minPx) / vwRange
        let slopeVw = round4(slopePx * 100)
        let interceptRem = round4((minPx - slopePx * minVwPx) / 16.0)
        let minRem = round4(minPx / 16.0)
        let maxRem = round4(maxPx / 16.0)
        return "clamp(\(formatNum(minRem))rem, \(formatNum(interceptRem))rem + \(formatNum(slopeVw))vw, \(formatNum(maxRem))rem)"
    }

    private static func spacingVars(_ s: ThemeSettings) -> [CSSVariable] {
        guard let sp = s.spacing else { return [] }
        var v: [CSSVariable] = []
        for p in sp.spacingSizes ?? [] {
            v.append(.init(name: "--wp--preset--spacing--\(slug(p.slug))", value: p.size))
        }
        if (sp.spacingSizes ?? []).isEmpty, let scale = sp.spacingScale {
            v += generateSpacingScale(scale)
        }
        return v
    }

    private static func generateSpacingScale(_ scale: SpacingScale) -> [CSSVariable] {
        let op = scale.operator ?? "*"
        let increment = scale.increment ?? 1.5
        let steps = scale.steps ?? 7
        let mediumStep = scale.mediumStep ?? 1.5
        let unit = scale.unit ?? "rem"
        guard steps >= 1 else { return [] }
        var sizes: [Double] = [mediumStep]
        var cur = mediumStep
        let medIndex = steps / 2
        for _ in 0..<medIndex {
            cur = op == "*" ? cur / increment : cur - increment
            sizes.insert(max(cur, 0.01), at: 0)
        }
        cur = mediumStep
        for _ in 0..<(steps - medIndex - 1) {
            cur = op == "*" ? cur * increment : cur + increment
            sizes.append(cur)
        }
        return sizes.enumerated().map { i, size in
            CSSVariable(name: "--wp--preset--spacing--\((i + 1) * 10)", value: "\(formatNum(size))\(unit)")
        }
    }

    private static func borderVars(_ s: ThemeSettings) -> [CSSVariable] {
        (s.border?.radiusSizes ?? []).map {
            .init(name: "--wp--preset--border-radius--\(slug($0.slug))", value: $0.size)
        }
    }

    private static func shadowVars(_ s: ThemeSettings) -> [CSSVariable] {
        (s.shadow?.presets ?? []).map {
            .init(name: "--wp--preset--shadow--\(slug($0.slug))", value: $0.shadow)
        }
    }

    private static func dimensionVars(_ s: ThemeSettings) -> [CSSVariable] {
        (s.dimensions?.dimensionSizes ?? []).map {
            .init(name: "--wp--preset--dimension--\(slug($0.slug))", value: $0.size)
        }
    }

    private static func customVars(_ s: ThemeSettings) -> [CSSVariable] {
        guard let raw = s.custom?.value, let dict = raw as? [String: Any] else { return [] }
        var v: [CSSVariable] = []
        flattenCustom(dict, prefix: "--wp--custom", into: &v)
        return v
    }

    private static func flattenCustom(_ dict: [String: Any], prefix: String, into v: inout [CSSVariable]) {
        for key in dict.keys.sorted() {
            let newPrefix = "\(prefix)--\(slug(key))"
            switch dict[key] {
            case let nested as [String: Any]: flattenCustom(nested, prefix: newPrefix, into: &v)
            case let val?: v.append(.init(name: newPrefix, value: "\(val)"))
            default: break
            }
        }
    }

    // MARK: Helpers

    static func slug(_ input: String) -> String {
        input.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "_", with: "-")
    }

    static func toPx(_ value: String) -> Double? {
        let t = value.trimmingCharacters(in: .whitespaces)
        if t.hasSuffix("px"), let n = Double(t.dropLast(2)) { return n }
        if t.hasSuffix("rem"), let n = Double(t.dropLast(3)) { return n * 16 }
        if t.hasSuffix("em"), let n = Double(t.dropLast(2)) { return n * 16 }
        return Double(t)
    }

    private static func round4(_ n: Double) -> Double { (n * 10000).rounded() / 10000 }

    static func formatNum(_ n: Double) -> String {
        if n == n.rounded() && abs(n) < 1e9 { return String(Int(n)) }
        var s = String(format: "%.4f", n)
        while s.hasSuffix("0") { s = String(s.dropLast()) }
        if s.hasSuffix(".") { s = String(s.dropLast()) }
        return s
    }
}
