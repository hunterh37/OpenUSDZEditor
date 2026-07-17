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

/// Enterprise-grade session/command edge cases: multi-op labeling, undo on a
/// clean session, journal trimming after in-session undo, and UV-channel
/// authoring with the faceVarying interpolation contract.
@Suite("MeshEditSession edge cases")
struct MeshEditSessionEdgeCaseTests {

    @Test func multiOpCommitLabelCountsOps() throws {
        var session = try MeshEditSession(path: PrimPath("/Root/Panel")!, flat: quadFlat())
        let inset = try InsetFaces.apply(session.mesh, selection: .faces([FaceID(0)]),
                                         params: .init(fraction: 0.25))
        session.record(inset, journalEntry: "Inset f=0.25")
        guard case .faces(let inner) = inset.resultSelection else {
            Issue.record("expected face selection"); return
        }
        let extrude = try ExtrudeFaces.apply(session.mesh, selection: .faces(inner),
                                             params: .init(distance: 0.5))
        session.record(extrude, journalEntry: "Extrude d=0.5")

        let command = try #require(session.commitCommand())
        #expect(command.label == "Mesh Edit (2 ops) (Panel)")
        #expect(command.before == quadFlat())
        #expect(session.journal == ["Inset f=0.25", "Extrude d=0.5"])
    }

    @Test func undoOnCleanSessionIsSafeNoOp() throws {
        var session = try MeshEditSession(path: PrimPath("/Root/Panel")!, flat: quadFlat())
        let hash = session.mesh.topologyHash
        session.undo() // empty stack — must not trap or corrupt state
        session.undo()
        #expect(session.mesh.topologyHash == hash)
        #expect(!session.isDirty)
        #expect(!session.canUndo)
        #expect(session.commitCommand() == nil)
    }

    /// After undoing one of two ops, the journal must shrink in lockstep and a
    /// commit must label itself as the single surviving op — a stale "(2 ops)"
    /// label would misdescribe the undo entry in the Edit menu.
    @Test func undoTrimsJournalAndCommitLabelFollows() throws {
        var session = try MeshEditSession(path: PrimPath("/Root/Panel")!, flat: quadFlat())
        let first = try ExtrudeFaces.apply(session.mesh, selection: .faces([FaceID(0)]),
                                           params: .init(distance: 0.5))
        session.record(first, journalEntry: "Extrude d=0.5")
        let second = try InsetFaces.apply(session.mesh, selection: .faces([FaceID(0)]),
                                          params: .init(fraction: 0.5))
        session.record(second, journalEntry: "Inset f=0.5")

        session.undo()
        #expect(session.journal == ["Extrude d=0.5"])
        #expect(session.canUndo)
        let command = try #require(session.commitCommand())
        #expect(command.label == "Extrude d=0.5 (Panel)")
        // The committed mesh is the first op's result, not the second's.
        #expect(command.after.points.count == 8)
        #expect(command.after.faceVertexCounts == first.mesh.faceOrder.map { first.mesh.faceLoops[$0]!.count })
    }

    /// When the edited mesh carries UVs, the command must author `primvars:st`
    /// as a flat double array (2 per corner) with faceVarying interpolation —
    /// and undo must restore the original arrays.
    @Test func commandAuthorsUVChannelWithFaceVaryingInterpolation() throws {
        var after = quadFlat()
        after.faceVaryingUVs = [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)]
        let path = PrimPath("/Root/Panel")!
        let command = MeshEditCommand(path: path, before: quadFlat(), after: after, opLabel: "UV Test")

        let stage = meshStage()
        try command.execute(on: stage)
        let prim = try #require(stage.prim(at: path))
        let st = try #require(prim.attribute(named: "primvars:st"))
        guard case .doubleArray(let uvs) = st.value else {
            Issue.record("primvars:st not authored as doubleArray"); return
        }
        #expect(uvs == [0, 0, 1, 0, 1, 1, 0, 1])
        #expect(st.metadata["interpolation"] == "faceVarying")

        try command.undo(on: stage)
        let restored = try #require(stage.prim(at: path))
        guard case .float3Array(let pts)? = restored.attribute(named: "points")?.value else {
            Issue.record("points missing after undo"); return
        }
        #expect(pts.count == quadFlat().points.count * 3)
    }
}
