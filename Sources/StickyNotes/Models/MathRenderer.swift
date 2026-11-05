import Foundation

/// Supported math rendering engines for markdown equations
enum MathRenderer: String, CaseIterable, Codable {
    case typst = "typst"
    case latex = "latex"

    var displayName: String {
        switch self {
        case .typst: return "Typst"
        case .latex: return "LaTeX (KaTeX)"
        }
    }

    static func from(_ value: String) -> MathRenderer {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "latex", "katex", "tex":
            return .latex
        case "typst", "typlet":
            return .typst
        default:
            return .typst
        }
    }
}
