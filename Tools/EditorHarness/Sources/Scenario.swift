import Foundation

/// A scripted harness run, authored as JSON so a run is reviewable and
/// re-runnable rather than a pile of ad-hoc flags.
///
/// ```json
/// { "name": "material-edit",
///   "open": "Tests/Fixtures/car.usda",
///   "steps": [
///     { "do": "select", "path": "/Car/Body" },
///     { "do": "shot", "name": "before", "tab": "material" },
///     { "do": "material.set", "input": "roughness", "number": 0.9 },
///     { "do": "expect", "materialInput": "roughness", "number": 0.9 },
///     { "do": "undo" },
///     { "do": "expect", "materialInput": "roughness", "number": 0.4 }
///   ] }
/// ```
struct Scenario: Decodable {
    var name: String
    /// Stage to open through the real bridge. Relative paths resolve against
    /// the scenario file's directory.
    var open: String
    var steps: [Step]

    struct Step: Decodable {
        /// The verb. See `Driver` for the dispatch table.
        var `do`: String

        // Operands — each verb reads the ones it needs.
        var path: String?
        var name: String?
        var tab: String?
        var input: String?
        var number: Double?
        var color: [Double]?
        var string: String?
        var count: Int?

        // Expectations.
        /// Assert the named input's value (with `number`/`color`, or `isNull`).
        var materialInput: String?
        /// Assert the input carries no authored opinion.
        var isNull: Bool?
        /// Assert which prim the selection's material inputs resolve to.
        var surfacePath: String?
    }
}

enum HarnessError: Error, CustomStringConvertible {
    case usage(String)
    case badScenario(String)
    case renderFailed(String)
    case stepFailed(step: Int, verb: String, detail: String)
    case expectationFailed(step: Int, detail: String)

    var description: String {
        switch self {
        case .usage(let s): return s
        case .badScenario(let s): return "bad scenario: \(s)"
        case .renderFailed(let s): return "could not render \(s)"
        case let .stepFailed(step, verb, detail):
            return "step \(step) (\(verb)) failed: \(detail)"
        case let .expectationFailed(step, detail):
            return "step \(step) expectation failed: \(detail)"
        }
    }
}
