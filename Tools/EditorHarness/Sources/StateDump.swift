import Foundation
import USDCore
import EditingKit
import EditorUI

/// Text rendering of document state — the harness's non-pixel observation.
///
/// A PNG shows what a panel looks like; this shows what the document *holds*.
/// Diffing two dumps across a step is usually a faster read than diffing two
/// screenshots.
@MainActor
enum StateDump {

    static func text(_ document: EditorDocument) -> String {
        var lines: [String] = []
        let stage = document.snapshot
        lines.append("stage: \(stage.sourceURL?.lastPathComponent ?? "(scratch)") — \(stage.primCount) prims")
        lines.append("  upAxis=\(stage.metadata.upAxis.rawValue) metersPerUnit=\(stage.metadata.metersPerUnit) defaultPrim=\(stage.metadata.defaultPrim ?? "—")")
        lines.append("  undo=\(document.undoLabel ?? "—") redo=\(document.redoLabel ?? "—")")

        if let path = document.selection.primary, let prim = stage.prim(at: path) {
            lines.append("selection: \(path) (\(prim.typeName))")
            if let material = document.boundMaterial(for: path) {
                lines.append("  material: \(material.material.path) surface=\(material.surfacePath)")
                for input in PreviewSurfaceInput.catalog {
                    guard let value = document.materialInput(input, on: material) else { continue }
                    lines.append("    \(input.name) = \(value)  [authored]")
                }
            } else {
                lines.append("  material: (none bound)")
            }
        } else {
            lines.append("selection: (none)")
        }
        return lines.joined(separator: "\n")
    }
}
