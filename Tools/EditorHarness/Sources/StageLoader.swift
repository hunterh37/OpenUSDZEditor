import Foundation
import USDCore
import USDBridge

/// Opens a stage through the **real** bridge — the same subprocess +
/// `stage_snapshot.py` path the app's Open… uses.
///
/// This is the point of running the harness against real files: bugs like "the
/// snapshot never carried relationships, so no mesh ever resolved its material"
/// only exist on this path. A hand-built `StageSnapshot` would have hidden it.
enum StageLoader {

    static func load(_ url: URL) async throws -> StageSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw HarnessError.badScenario("no file at \(url.path)")
        }
        guard let executor = ProcessBridgeExecutor(scriptPath: snapshotScriptPath) else {
            throw HarnessError.badScenario(
                "no Python interpreter found (set DICYANIN_SNAPSHOT_SCRIPT / install usd-core)")
        }
        return try await BridgedStage.open(url: url, executor: executor).snapshot
    }

    /// Mirrors the app's resolution (`DICYANIN_SNAPSHOT_SCRIPT`, else walk up for
    /// `Resources/Python`), so the harness and the app can never disagree about
    /// which script ran.
    static var snapshotScriptPath: String {
        if let override = ProcessInfo.processInfo.environment["DICYANIN_SNAPSHOT_SCRIPT"],
           !override.isEmpty {
            return override
        }
        guard let root = RepoRoot.find() else { return RepoRoot.marker }
        return root.appendingPathComponent(RepoRoot.marker).path
    }
}
