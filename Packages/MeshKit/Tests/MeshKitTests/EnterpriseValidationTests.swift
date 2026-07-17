import Testing
import Foundation
@testable import MeshKit

/// Enterprise-grade validation: each test targets a distinct, previously
/// uncovered failure mode in the mesh-editing stack — precondition rejection
/// paths (bowtie, non-manifold, normal cancellation), attribute-channel
/// integrity (UVs, subsets), analytic geometry checks, and degenerate-input
/// handling in MeshIO and MergeVertices.
@Suite("Enterprise validation — MeshKit")
struct EnterpriseValidationTests {

    // MARK: - Extrude precondition rejection paths

    /// A vertex interior to the selected region (no incident region-boundary
    /// edge) that still touches an unselected face is a bowtie — extrude must
    /// refuse with a diagnostic instead of producing ambiguous topology.
    @Test func extrudeRejectsBowtieVertex() throws {
        // 4-triangle fan around center v0 + a quad attached at v0 only.
        let flat = FlatMesh(
            points: [
                SIMD3(0, 0, 0),                                    // v0 center
                SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(-1, 0, 0), SIMD3(0, -1, 0), // ring
                SIMD3(1, 1, 1), SIMD3(2, 1, 1), SIMD3(2, 0, 1),   // bowtie quad
            ],
            faceVertexCounts: [3, 3, 3, 3, 4],
            faceVertexIndices: [
                0, 1, 2,  0, 2, 3,  0, 3, 4,  0, 4, 1, // fan
                0, 5, 6, 7,                             // quad sharing only v0
            ])
        let mesh = try MeshIO.mesh(from: flat)
        let fan = Set((0..<4).map(FaceID.init))
        #expect {
            _ = try ExtrudeFaces.apply(mesh, selection: .faces(fan), params: .init(distance: 0.5))
        } throws: { error in
            guard case MeshOpError.preconditionFailed(let msg) = error else { return false }
            return msg.contains("bowtie")
        }
    }

    /// Selecting opposite faces of a cube makes area-weighted normals cancel;
    /// averaged-normal extrude must fail with the "pass an explicit axis" hint
    /// rather than extruding along a garbage direction.
    @Test func extrudeRejectsCancellingRegionNormals() throws {
        let cube = Fixtures.cube()
        let topAndBottom: Set<FaceID> = [FaceID(0), FaceID(1)]
        #expect {
            _ = try ExtrudeFaces.apply(cube, selection: .faces(topAndBottom),
                                       params: .init(distance: 0.5, direction: .averagedNormal))
        } throws: { error in
            guard case MeshOpError.preconditionFailed(let msg) = error else { return false }
            return msg.contains("axis")
        }
    }

    /// An edge bordered by three faces is non-manifold; extruding any face
    /// touching it must throw `.nonManifoldRegion` before mutating anything.
    @Test func extrudeRejectsNonManifoldEdge() throws {
        let flat = FlatMesh(
            points: [SIMD3(0, 0, 0), SIMD3(0, 0, 1), SIMD3(1, 0, 0),
                     SIMD3(-1, 0, 0), SIMD3(0, 1, 0)],
            faceVertexCounts: [3, 3, 3],
            faceVertexIndices: [0, 1, 2,  0, 3, 1,  0, 1, 4]) // all share edge (0,1)
        let mesh = try MeshIO.mesh(from: flat)
        #expect {
            _ = try ExtrudeFaces.apply(mesh, selection: .faces([FaceID(0)]),
                                       params: .init(distance: 1))
        } throws: { error in
            if case MeshOpError.nonManifoldRegion = error { return true }
            return false
        }
    }

    /// The explicit axis must be normalized before scaling by `distance`:
    /// axis (0,0,10) with distance 0.5 moves the cap exactly 0.5, not 5.
    @Test func extrudeNormalizesExplicitAxis() throws {
        let cube = Fixtures.cube()
        let result = try ExtrudeFaces.apply(cube, selection: .faces([Fixtures.cubeTop]),
                                            params: .init(distance: 0.5, direction: .axis(SIMD3(0, 0, 10))))
        // Unit cube + 1×1×0.5 slab = 1.5 exactly.
        #expect(abs(result.mesh.signedVolume - 1.5) < 1e-12)
        let capZ = result.mesh.faceLoops[Fixtures.cubeTop]!.map { result.mesh.positions[$0]!.z }
        #expect(capZ.allSatisfy { abs($0 - 1.5) < 1e-12 })
    }

    /// The base ring must keep its original positions after an extrude — only
    /// the cap is retargeted onto duplicated vertices.
    @Test func extrudeLeavesBaseRingInPlace() throws {
        let cube = Fixtures.cube()
        let baseLoop = cube.faceLoops[Fixtures.cubeTop]!
        let basePositions = baseLoop.map { cube.positions[$0]! }
        let result = try ExtrudeFaces.apply(cube, selection: .faces([Fixtures.cubeTop]),
                                            params: .init(distance: 1))
        for (v, p) in zip(baseLoop, basePositions) {
            #expect(result.mesh.positions[v] == p, "boundary vertex \(v.rawValue) moved")
        }
        #expect(result.resultSelection == .faces([Fixtures.cubeTop]))
    }

    // MARK: - Inset edge cases

    /// A selection mixing valid and unknown faces must throw
    /// `.unknownComponent` — never partially apply.
    @Test func insetRejectsSelectionWithUnknownFace() throws {
        let cube = Fixtures.cube()
        #expect {
            _ = try InsetFaces.apply(cube, selection: .faces([FaceID(0), FaceID(99)]),
                                     params: .init(fraction: 0.5))
        } throws: { error in
            if case MeshOpError.unknownComponent = error { return true }
            return false
        }
    }

    /// Insetting two adjacent cube faces: per-face delta V+n E+2n F+n must sum,
    /// invariants hold, and — because inset geometry is coplanar with each
    /// original face — the enclosed volume is bit-identical.
    @Test func insetAdjacentFacesPreservesVolume() throws {
        let cube = Fixtures.cube()
        let result = try InsetFaces.apply(cube, selection: .faces([FaceID(0), FaceID(2)]),
                                          params: .init(fraction: 0.3))
        #expect(result.delta == TopologyDelta(vertices: 8, edges: 16, faces: 8))
        #expect(abs(result.mesh.signedVolume - cube.signedVolume) < 1e-12)
        guard case .faces(let inner) = result.resultSelection else {
            Issue.record("expected face selection"); return
        }
        #expect(inner.count == 2)
        #expect(MeshInvariants.violations(in: result.mesh).isEmpty)
    }

    // MARK: - FillHole rejection paths

    @Test func fillHoleRejectsFaceSelection() throws {
        let openBox = Fixtures.openBox()
        #expect {
            _ = try FillHole.apply(openBox, selection: .faces([FaceID(0)]))
        } throws: { error in
            if case MeshOpError.preconditionFailed = error { return true }
            return false
        }
    }

    /// Two boundary loops meeting at one vertex (bowtie surface) are ambiguous
    /// for the boundary walk — must throw `.nonManifoldRegion`, not loop or
    /// fill the wrong hole.
    @Test func fillHoleRejectsTwoLoopsSharingAVertex() throws {
        let flat = FlatMesh(
            points: [SIMD3(0, 0, 0),
                     SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0),
                     SIMD3(-1, 0, 0), SIMD3(-1, -1, 0), SIMD3(0, -1, 0)],
            faceVertexCounts: [4, 4],
            faceVertexIndices: [0, 1, 2, 3,  0, 4, 5, 6]) // quads share only v0
        let mesh = try MeshIO.mesh(from: flat)
        #expect {
            _ = try FillHole.apply(mesh, selection: .edges([EdgeKey(VertexID(1), VertexID(2))]))
        } throws: { error in
            if case MeshOpError.nonManifoldRegion = error { return true }
            return false
        }
    }

    // MARK: - MergeVertices degeneration

    /// Welding the shared edge of a two-triangle strip degenerates both faces;
    /// everything must be removed, pruned, and the survivor selection must not
    /// reference pruned vertices.
    @Test func mergeCollapsingAllFacesLeavesEmptyValidMesh() throws {
        let flat = FlatMesh(
            points: [SIMD3(0, 0, 0), SIMD3(0, 1, 0), SIMD3(1, 0.5, 0), SIMD3(-1, 0.5, 0)],
            faceVertexCounts: [3, 3],
            faceVertexIndices: [0, 1, 2,  0, 3, 1]) // share edge (0,1)
        let mesh = try MeshIO.mesh(from: flat)
        let result = try MergeVertices.apply(mesh, selection: .vertices([VertexID(0), VertexID(1)]),
                                             params: .toVertex(VertexID(0)))
        #expect(result.mesh.faceCount == 0)
        #expect(result.mesh.vertexCount == 0)
        #expect(result.resultSelection == .vertices([]))
        #expect(MeshInvariants.violations(in: result.mesh).isEmpty)
    }

    // MARK: - MeshIO channel integrity

    @Test func meshIORejectsUVCountMismatch() {
        var flat = Fixtures.cubeFlat()
        flat.faceVaryingUVs = [SIMD2(0, 0), SIMD2(1, 0)] // 2 UVs for 24 corners
        #expect {
            _ = try MeshIO.mesh(from: flat)
        } throws: { error in
            if case MeshOpError.preconditionFailed = error { return true }
            return false
        }
    }

    @Test func meshIORejectsSubsetFaceIndexOutOfRange() {
        var flat = Fixtures.cubeFlat()
        flat.subsets = ["metal": [0, 6]] // face 6 doesn't exist
        #expect {
            _ = try MeshIO.mesh(from: flat)
        } throws: { error in
            if case MeshOpError.unknownComponent = error { return true }
            return false
        }
    }

    /// `replaceLoop` breaks per-corner attribute parallelism for that face, so
    /// export must drop the whole UV channel (partial channels are invalid USD)
    /// while keeping topology intact.
    @Test func replaceLoopInvalidatesUVChannelOnExport() throws {
        var flat = Fixtures.cubeFlat()
        flat.faceVaryingUVs = (0..<24).map { SIMD2(Double($0) / 24, 0.5) }
        var mesh = try MeshIO.mesh(from: flat)
        let face = FaceID(0)
        let rotated = Array(mesh.faceLoops[face]!.dropFirst()) + [mesh.faceLoops[face]![0]]
        mesh.replaceLoop(rotated, for: face)

        let exported = MeshIO.flat(from: mesh)
        #expect(exported.faceVaryingUVs.isEmpty, "partial UV channel must not be exported")
        #expect(exported.faceVertexCounts == flat.faceVertexCounts)
        #expect(exported.points == flat.points)
    }
}
