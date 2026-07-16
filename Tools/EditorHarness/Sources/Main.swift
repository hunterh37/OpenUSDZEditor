import Foundation

/// Offscreen harness for the editor's UI surface. See Tools/EditorHarness/README.md.
/// Exit codes: 0 ok, 1 step/expectation failure, 2 usage.
@main
struct Main {
    static func main() async {
        exit(await HarnessRunner.run(arguments: Array(CommandLine.arguments.dropFirst())))
    }
}

enum HarnessRunner {

    static let usage = """
    usage: editor-harness <subcommand>
      run <scenario.json> [--out DIR]
                          Drive the real editor document + panels through a
                          scripted scenario, offscreen. Writes screenshots and
                          a transcript to DIR (default: .harness-out).
      dump <file.usd[z|a|c]> [--select PRIM_PATH]
                          Open a stage through the real bridge and print its
                          resolved state (material binding, authored inputs).
      shot <file.usd[z|a|c]> --select PRIM_PATH [--tab TAB] [--out DIR]
                          Render one inspector panel to PNG. TAB is one of:
                          prim, transform, material, stage.

    Never opens a window or takes focus.
    """

    static func run(
        arguments: [String],
        print output: @escaping (String) -> Void = { print($0) },
        printError: (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    ) async -> Int32 {
        guard let subcommand = arguments.first else {
            printError(usage)
            return 2
        }
        let rest = Array(arguments.dropFirst())
        do {
            switch subcommand {
            case "run":     return try await runScenario(rest, print: output)
            case "dump":    return try await dump(rest, print: output)
            case "shot":    return try await shot(rest, print: output)
            case "-h", "--help", "help":
                output(usage)
                return 0
            default:
                printError("unknown subcommand '\(subcommand)'\n\n\(usage)")
                return 2
            }
        } catch let error as HarnessError {
            if case .usage(let detail) = error {
                printError("\(detail)\n\n\(usage)")
                return 2
            }
            printError("error: \(error)")
            return 1
        } catch {
            printError("error: \(error)")
            return 1
        }
    }

    // MARK: Subcommands

    private static func runScenario(_ args: [String], print output: (String) -> Void) async throws -> Int32 {
        guard let path = args.first, !path.hasPrefix("--") else {
            throw HarnessError.usage("run needs a scenario file")
        }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let data = try Data(contentsOf: url)
        let scenario: Scenario
        do {
            scenario = try JSONDecoder().decode(Scenario.self, from: data)
        } catch {
            throw HarnessError.badScenario("\(url.lastPathComponent): \(error)")
        }
        let out = outDirectory(args, default: ".harness-out")
            .appendingPathComponent(scenario.name)

        let driver = await Driver(
            outputDirectory: out, baseDirectory: url.deletingLastPathComponent())
        output("▶︎ \(scenario.name)")
        do {
            try await driver.run(scenario)
        } catch {
            await writeReport(driver, to: out, scenario: scenario, failure: "\(error)")
            throw error
        }
        await writeReport(driver, to: out, scenario: scenario, failure: nil)
        let shotCount = await driver.shots.count
        output("✓ \(scenario.name) — \(shotCount) shot(s) → \(out.path)")
        return 0
    }

    private static func dump(_ args: [String], print output: @escaping (String) -> Void) async throws -> Int32 {
        guard let path = args.first, !path.hasPrefix("--") else {
            throw HarnessError.usage("dump needs a stage file")
        }
        var steps: [Scenario.Step] = []
        if let select = value(of: "--select", in: args) {
            steps.append(Scenario.Step(do: "select", path: select))
        }
        steps.append(Scenario.Step(do: "dump"))
        return try await drive(
            Scenario(name: "dump", open: path, steps: steps), out: nil, print: output)
    }

    private static func shot(_ args: [String], print output: @escaping (String) -> Void) async throws -> Int32 {
        guard let path = args.first, !path.hasPrefix("--") else {
            throw HarnessError.usage("shot needs a stage file")
        }
        guard let select = value(of: "--select", in: args) else {
            throw HarnessError.usage("shot needs --select")
        }
        let tab = value(of: "--tab", in: args) ?? "material"
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let scenario = Scenario(name: "\(name)-\(tab)", open: path, steps: [
            Scenario.Step(do: "select", path: select),
            Scenario.Step(do: "shot", name: "\(name)-\(tab)", tab: tab),
        ])
        return try await drive(
            scenario, out: outDirectory(args, default: ".harness-out"), print: output)
    }

    /// Shared path for the ad-hoc subcommands, which are just short scenarios.
    private static func drive(
        _ scenario: Scenario, out: URL?, print output: @escaping (String) -> Void
    ) async throws -> Int32 {
        let directory = out ?? URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-\(UUID().uuidString)")
        let driver = await Driver(
            outputDirectory: directory,
            baseDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        try await driver.run(scenario)
        return 0
    }

    // MARK: Args

    private static func outDirectory(_ args: [String], default fallback: String) -> URL {
        URL(fileURLWithPath: value(of: "--out", in: args) ?? fallback).standardizedFileURL
    }

    private static func value(of flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    /// Writes the transcript next to the screenshots so a run is self-describing
    /// — someone reading the output directory can see what was driven and what
    /// each shot shows, without re-running anything.
    @MainActor
    private static func writeReport(
        _ driver: Driver, to directory: URL, scenario: Scenario, failure: String?
    ) {
        var lines = ["# \(scenario.name)", "", "stage: \(scenario.open)", ""]
        lines += driver.transcript.map { "- \($0)" }
        if let failure {
            lines += ["", "## FAILED", "", "```", failure, "```"]
        }
        if !driver.shots.isEmpty {
            lines += ["", "## Shots", ""] + driver.shots.map { "- \($0.lastPathComponent)" }
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(
            to: directory.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
    }
}
