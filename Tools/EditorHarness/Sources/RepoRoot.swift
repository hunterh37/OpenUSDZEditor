import Foundation

/// Locates the workspace root so scenarios can name paths the way a human reads
/// them — `Tests/Fixtures/car.usda`, not `../../../Tests/Fixtures/car.usda`.
///
/// The marker is the bridge script: the harness can't do anything useful without
/// it, so a tree that lacks it isn't a workspace root worth finding.
enum RepoRoot {
    static let marker = "Resources/Python/stage_snapshot.py"

    /// Walks up from `start` looking for the marker. `nil` when `start` isn't
    /// inside a workspace.
    static func find(from start: URL) -> URL? {
        var dir = start.standardizedFileURL
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent(marker).path) {
                return dir
            }
            let parent = dir.deletingLastPathComponent()
            if parent == dir { break }   // hit "/"
            dir = parent
        }
        return nil
    }

    /// The workspace root, searched from the current directory then from `hint`
    /// (typically the scenario file's location, which is inside the repo even
    /// when the tool is invoked from elsewhere).
    static func find(hint: URL? = nil) -> URL? {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return find(from: cwd) ?? hint.flatMap { find(from: $0) }
    }
}
