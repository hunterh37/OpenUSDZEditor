import SwiftUI
import USDCore
import DicyaninDesignSystem

/// SwiftUI bridges for the pure design-system tokens. Kept in one place so
/// every panel in EditorUI shares identical chrome (specs/design-system.md).
extension ColorToken {
    /// Maps a design-system token to SwiftUI.
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

/// A titled panel section: a small uppercase caption over its content, matching
/// the enterprise-restrained inspector look.
struct PanelSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title.uppercased())
                .font(.system(size: TypeScale.label, weight: .semibold))
                .foregroundStyle(Palette.textSecondary.color)
                .tracking(0.5)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A label/value row used throughout the inspector. The value is monospaced so
/// numbers line up column-wise.
struct FieldRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(label)
                .font(.system(size: TypeScale.body))
                .foregroundStyle(Palette.textSecondary.color)
                .frame(width: 96, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: TypeScale.inspectorField, design: .monospaced))
                .foregroundStyle(Palette.textPrimary.color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Human-readable rendering of a typed USD attribute value for the inspector.
enum ValueFormatter {
    static func string(_ value: AttributeValue) -> String {
        switch value {
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .double(let d): return trimmed(d)
        case .string(let s): return "\"\(s)\""
        case .token(let t): return t
        case .asset(let a): return "@\(a)@"
        case .vector(let v): return "(" + v.map(trimmed).joined(separator: ", ") + ")"
        case .matrix4: return "matrix4d(…)"
        case .intArray(let a): return array(a.map(String.init))
        case .doubleArray(let a): return array(a.map(trimmed))
        case .stringArray(let a): return array(a)
        case .tokenArray(let a): return array(a)
        case .float3Array(let a): return "float3[\(a.count / 3)]"
        case .quatfArray(let a): return "quatf[\(a.count / 4)]"
        case .matrix4dArray(let a): return "matrix4d[\(a.count / 16)]"
        case .unsupported(let name): return "‹\(name)›"
        }
    }

    private static func trimmed(_ d: Double) -> String {
        if d == d.rounded() && abs(d) < 1e15 { return String(Int(d)) }
        return String(format: "%.4g", d)
    }

    private static func array(_ items: [String]) -> String {
        let shown = items.prefix(6).joined(separator: ", ")
        return items.count > 6 ? "[\(shown), … +\(items.count - 6)]" : "[\(shown)]"
    }
}
