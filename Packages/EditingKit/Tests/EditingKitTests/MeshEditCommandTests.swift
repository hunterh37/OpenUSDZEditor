import Testing
import Foundation
import USDCore
import MeshKit
@testable import EditingKit

private func quadFlat() -> FlatMesh {
    FlatMesh(points: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0)],
             faceVertexCounts: [4],
             faceVertexIndices: [0, 1, 2, 3])
}

private func meshStage() -> InMemoryStage {
    let prim = Prim(path: PrimPath("/Root/Panel")!, typeName: "Mesh")
    let root = Prim(path: PrimPath("/Root")!, typeName: "Xform", children: [prim])
    return InMemoryStage(StageSnapshot(rootPrims: [root]))
}

@Suite("MeshEditSession")
struct MeshEditSessionTests {

    @Test func sessionAppliesOpAndCommits() throws {
        var session = try MeshEditSession(path: PrimPath("/Root/Panel")!, flat: quadFlat())
        let result = try ExtrudeFaces.apply(session.mesh, selection: .faces([FaceID(0)]),
                                            params: .init(distance: 0.5))
        session.record(result, journalEntry: "Extrude")
        #expect(session.isDirty)
        #expect(session.journal == ["Extrude"])

        let command = try #require(session.commitCommand())
        #expect(command.label == "Extrude (Panel)")
        #expect(command.after.points.count == 8)
        #expect(command.before == quadFlat())
    }

    @Test func sessionUndoRestoresWorkingMesh() throws {
        var session = try MeshEditSession(path: PrimPath("/Root/Panel")!, flat: quadFlat())
        let hashBefore = session.mesh.topologyHash
        let result = try InsetFaces.apply(session.mesh, selection: .faces([FaceID(0)]),
                                          params: .init(fraction: 0.25))
        session.record(result, journalEntry: "Inset")
        session.undo()
        #expect(session.mesh.topologyHash == hashBefore)
        #expect(!session.isDirty)
        #expect(session.commitCommand() == nil)
    }

    @Test func sessionRefusesSkinnedMesh() {
        var flat = quadFlat()
        flat.hasSkeletalBinding = true
        #expect(throws: MeshOpError.skinnedMeshUnsupported) {
            _ = try MeshEditSession(path: PrimPath("/Root/Panel")!, flat: flat)
        }
    }
}

@Suite("MeshEditCommand")
struct MeshEditCommandTests {

    @Test func executeAuthorsArraysAndUndoRestores() throws {
        let stage = meshStage()
        let path = PrimPath("/Root/Panel")!
        var session = try MeshEditSession(path: path, flat: quadFlat())
        let result = try ExtrudeFaces.apply(session.mesh, selection: .faces([FaceID(0)]),
                                            params: .init(distance: 1))
        session.record(result, journalEntry: "Extrude")
        let command = try #require(session.commitCommand())

        try command.execute(on: stage)
        let prim = try #require(stage.prim(at: path))
        guard case .intArray(let counts)? = prim.attribute(named: "faceVertexCounts")?.value else {
            Issue.record("faceVertexCounts not authored"); return
        }
        #expect(counts == command.after.faceVertexCounts)
        guard case .float3Array(let pts)? = prim.attribute(named: "points")?.value else {
            Issue.record("points not authored"); return
        }
        #expect(pts.count == command.after.points.count * 3)

        try command.undo(on: stage)
        let restored = try #require(stage.prim(at: path))
        guard case .intArray(let restoredCounts)? = restored.attribute(named: "faceVertexCounts")?.value else {
            Issue.record("faceVertexCounts missing after undo"); return
        }
        #expect(restoredCounts == [4])
    }
}
