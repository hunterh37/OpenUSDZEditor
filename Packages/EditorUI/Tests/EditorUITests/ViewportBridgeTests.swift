import Testing
import Foundation
import USDCore
import MeshKit
import ViewportKit
@testable import EditorUI

@MainActor
private func makeCubeDocument() -> (EditorDocument, PrimPath) {
    let path = PrimPath("/Cube")!
    // Unit cube, matching Tests/Fixtures/test-cube.usda.
    let mesh = Prim(
        path: path, typeName: "Mesh",
        attributes: [
            Attribute(name: "points", value: .float3Array([
                0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0,
                0, 0, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1,
            ])),
            Attribute(name: "faceVertexCounts", value: .intArray([4, 4, 4, 4, 4, 4])),
            Attribute(name: "faceVertexIndices", value: .intArray([
                0, 3, 2, 1, 4, 5, 6, 7, 0, 1, 5, 4,
                2, 3, 7, 6, 1, 2, 6, 5, 3, 0, 4, 7,
            ])),
        ])
    return (EditorDocument(snapshot: StageSnapshot(rootPrims: [mesh])), path)
}

@MainActor
@Suite("Viewport bridge (edit mode ↔ RealityKit data)")
struct ViewportBridgeTests {

    @Test func noEditedMeshOutsideEditMode() {
        let (doc, _) = makeCubeDocument()
        #expect(doc.viewportEditedMesh == nil)
    }

    @Test func editModePublishesLiveGeometryWithSelection() {
        let (doc, path) = makeCubeDocument()
        doc.enterMeshEditMode(at: path)
        let data = doc.viewportEditedMesh
        #expect(data?.primName == "Cube")
        #expect(data?.positions.count == 8)
        #expect(data?.faceLoops.count == 6)
        #expect(data?.selectedFaces == [0]) // default first-face selection
    }

    @Test func viewportPickDrivesTheSameSelectionAsTheHUD() {
        let (doc, path) = makeCubeDocument()
        doc.enterMeshEditMode(at: path)
        doc.pickMeshFace(index: 4)
        #expect(doc.meshEdit?.selectedFaceIndex == 4)
        #expect(doc.viewportEditedMesh?.selectedFaces == [4])
    }

    @Test func opsReflectImmediatelyInViewportData() {
        let (doc, path) = makeCubeDocument()
        doc.enterMeshEditMode(at: path)
        doc.meshEdit?.tool = .extrude
        doc.meshEdit?.extrudeDistance = 0.5
        doc.applyActiveMeshTool()
        let data = doc.viewportEditedMesh
        #expect(data?.faceLoops.count == 10) // 6 + 4 side quads
        #expect(data?.positions.count == 12) // 8 + 4 duplicated boundary verts
    }

    @Test func committedGeometryStaysLiveAfterExitAndAcrossUndo() {
        let (doc, path) = makeCubeDocument()
        doc.enterMeshEditMode(at: path)
        doc.meshEdit?.tool = .extrude
        doc.applyActiveMeshTool()
        doc.exitMeshEditMode(commit: true)
        // Stage, not file, is the source of truth after commit.
        #expect(doc.lastMeshEditPath == path)
        #expect(doc.viewportEditedMesh?.faceLoops.count == 10)
        doc.undo()
        #expect(doc.viewportEditedMesh?.faceLoops.count == 6)
        doc.redo()
        #expect(doc.viewportEditedMesh?.faceLoops.count == 10)
    }

    @Test func hoverPreviewDefaultsOnAndReportsHoveredFace() {
        let (doc, path) = makeCubeDocument()
        doc.enterMeshEditMode(at: path)
        #expect(doc.meshEdit?.hoverPreviewEnabled == true)
        #expect(doc.meshEdit?.hoveredFaceIndex == nil)
        doc.hoverMeshFace(index: 3)
        #expect(doc.meshEdit?.hoveredFaceIndex == 3)
        doc.hoverMeshFace(index: nil) // cursor left the mesh
        #expect(doc.meshEdit?.hoveredFaceIndex == nil)
    }

    @Test func hoverIsIgnoredOutsideEditMode() {
        let (doc, _) = makeCubeDocument()
        doc.hoverMeshFace(index: 2) // must not crash or create state
        #expect(doc.meshEdit == nil)
    }

    @Test func hoverDoesNotChangeSelection() {
        let (doc, path) = makeCubeDocument()
        doc.enterMeshEditMode(at: path)
        doc.hoverMeshFace(index: 5)
        #expect(doc.meshEdit?.selectedFaceIndex == 0) // hover previews, click selects
        #expect(doc.viewportEditedMesh?.selectedFaces == [0])
    }

    @Test func pickedRayHitsTheFaceTheViewportWouldPick() {
        let (doc, path) = makeCubeDocument()
        doc.enterMeshEditMode(at: path)
        let data = doc.viewportEditedMesh!
        // Ray straight at the front face (y = 0 plane is face index 2).
        let ray = CameraRay.Ray(origin: SIMD3(0.5, -5, 0.5), direction: SIMD3(0, 1, 0))
        let hit = MeshPicker.pickFace(ray: ray, in: data)
        #expect(hit?.faceIndex == 2)
    }
}
