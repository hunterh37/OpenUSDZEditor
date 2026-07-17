import Testing
import Foundation
@testable import ViewportKit

/// Enterprise-grade validation of the edited-mesh rendering/picking pipeline:
/// picker↔BVH ordering parity at shared corners, the `faces:` flatten filter,
/// Newell-normal degeneracy fallback, and ray-direction semantics.
@Suite("Enterprise validation — ViewportKit")
struct ViewportEnterpriseValidationTests {

    /// 2×1 quad strip in the z=0 plane: faces 0 and 1 share the edge x=1.
    private func twoQuadStrip() -> EditedMeshData {
        EditedMeshData(
            primName: "Strip",
            positions: [
                SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(2, 0, 0),
                SIMD3(0, 1, 0), SIMD3(1, 1, 0), SIMD3(2, 1, 0),
            ],
            faceLoops: [[0, 1, 4, 3], [1, 2, 5, 4]])
    }

    /// A ray straight through the shared edge hits both faces at the same t
    /// (modulo ulps). Both the brute-force picker and the BVH must tie-break
    /// to the lowest face index — divergence here means hover flicker.
    @Test func sharedEdgeTieBreaksToLowestFaceInBothPickers() {
        let data = twoQuadStrip()
        let ray = CameraRay.Ray(origin: SIMD3(1, 0.5, 5), direction: SIMD3(0, 0, -1))

        let brute = MeshPicker.pickFace(ray: ray, in: data)
        let bvh = PickAccelerator(data).pickFace(ray: ray)

        #expect(brute?.faceIndex == 0)
        #expect(bvh?.faceIndex == 0)
        #expect(abs((brute?.distance ?? -1) - 5) < 1e-9)
        #expect(abs((bvh?.distance ?? -1) - 5) < 1e-9)
    }

    /// Möller–Trumbore accepts back-face hits (editing an open shell from
    /// inside), but never hits behind the ray origin.
    @Test func backFaceHitsCountButBehindOriginNeverDoes() {
        let data = twoQuadStrip()

        // Pointing away from the plane: no hit from either implementation.
        let away = CameraRay.Ray(origin: SIMD3(0.5, 0.5, 1), direction: SIMD3(0, 0, 1))
        #expect(MeshPicker.pickFace(ray: away, in: data) == nil)
        #expect(PickAccelerator(data).pickFace(ray: away) == nil)

        // Approaching from behind the winding (back face): must still hit.
        let behind = CameraRay.Ray(origin: SIMD3(0.5, 0.5, -1), direction: SIMD3(0, 0, 1))
        let hit = MeshPicker.pickFace(ray: behind, in: data)
        #expect(hit?.faceIndex == 0)
        #expect(abs((hit?.distance ?? -1) - 1) < 1e-9)
        #expect(PickAccelerator(data).pickFace(ray: behind) == hit)
    }

    /// `flatten(faces:)` renders exactly the requested faces (selection
    /// highlight pass) and silently skips out-of-range indices instead of
    /// crashing mid-frame.
    @Test func flattenFacesFilterRendersOnlyRequestedFaces() {
        let data = twoQuadStrip()
        let buffers = MeshFlattener.flatten(data, faces: [1, 99, -1])
        #expect(buffers.positions.count == 4)          // one quad's corners
        #expect(buffers.triangleIndices.count == 6)    // fan → 2 triangles
        #expect(buffers.normals.count == 4)
        // All emitted positions belong to face 1's loop.
        let expected = Set([1, 2, 5, 4].map { data.positions[$0] })
        #expect(Set(buffers.positions).isSubset(of: expected))
    }

    /// Collinear loops have no plane; the Newell fallback must return the
    /// documented (0,1,0) instead of NaN-poisoning the vertex buffer, while
    /// healthy planar loops produce an exact unit normal.
    @Test func newellNormalDegenerateFallbackAndPlanarExactness() {
        let collinear: [SIMD3<Float>] = [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(2, 0, 0)]
        #expect(MeshFlattener.newellNormal(collinear) == SIMD3(0, 1, 0))

        let square: [SIMD3<Float>] = [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0)]
        let n = MeshFlattener.newellNormal(square)
        #expect(abs(n.z - 1) < 1e-6 && abs(n.x) < 1e-6 && abs(n.y) < 1e-6)
    }
}
