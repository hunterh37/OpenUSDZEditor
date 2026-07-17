import Testing
import Foundation
import USDCore
import MeshKit
import USDBridge
@testable import EditorUI

@MainActor
private func makePanelDocument() -> (EditorDocument, PrimPath) {
    let path = PrimPath("/Panel")!
    let mesh = Prim(
        path: path, typeName: "Mesh",
        attributes: [
            Attribute(name: "points",
                      value: .float3Array([0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0])),
            Attribute(name: "faceVertexCounts", value: .intArray([4])),
            Attribute(name: "faceVertexIndices", value: .intArray([0, 1, 2, 3])),
        ])
    return (EditorDocument(snapshot: StageSnapshot(rootPrims: [mesh])), path)
}

@MainActor
@Suite("EditorDocument save")
struct DocumentSaveTests {

    private func tempUSDA() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("doc-save-\(UUID().uuidString).usda")
    }

    @Test func dirtyTrackingFollowsRevisions() async throws {
        let (doc, path) = makePanelDocument()
        #expect(!doc.hasUnsavedChanges)
        doc.setVisibility(path, .invisible)
        #expect(doc.hasUnsavedChanges)
        let url = tempUSDA()
        defer { try? FileManager.default.removeItem(at: url) }
        try await doc.save(to: url, executor: nil)
        #expect(!doc.hasUnsavedChanges)
        doc.undo()
        #expect(doc.hasUnsavedChanges) // undo past the save point is unsaved
    }

    @Test func saveFlushesALiveEditSessionFirst() async throws {
        let (doc, path) = makePanelDocument()
        doc.enterMeshEditMode(at: path)
        doc.meshEdit?.tool = .extrude
        doc.applyActiveMeshTool()
        let url = tempUSDA()
        defer { try? FileManager.default.removeItem(at: url) }
        try await doc.save(to: url, executor: nil)
        // What's on screen is what's saved: session committed, file has 5 faces.
        #expect(doc.meshEdit == nil)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("faceVertexCounts = [4, 4, 4, 4, 4]"))
        #expect(text.contains("point3f[] points")) // schema role type preserved
    }

    @Test func failedSaveKeepsDirtyFlag() async {
        let (doc, path) = makePanelDocument()
        doc.setVisibility(path, .invisible)
        // usdz without an executor must throw, leaving the document dirty.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("doc-save-\(UUID().uuidString).usdz")
        await #expect(throws: StageSaver.SaveError.pythonRequired("usdz")) {
            try await doc.save(to: url, executor: nil)
        }
        #expect(doc.hasUnsavedChanges)
    }
}
