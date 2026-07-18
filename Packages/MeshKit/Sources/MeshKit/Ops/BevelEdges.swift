import Foundation

/// Single-segment edge bevel with uniform width (specs/mesh-editing.md v1).
///
/// Each selected edge (a,b) is replaced by a quad: its endpoints slide apart
/// along the neighboring edges of the two adjacent faces, and the third face at
/// each endpoint gains a corner vertex (its loop grows by one).
///
/// Strict v1 preconditions (fail loudly, per op contract):
/// - every selected edge is interior (exactly 2 adjacent faces)
/// - selected edges are pairwise non-adjacent (no shared vertices)
/// - each endpoint has face-valence exactly 3 and only interior incident edges
/// - 0 < width < length of every slide edge (strictly, so nothing degenerates)
///
/// Predicted delta per edge: V += 2 (4 new, 2 removed), E += 3, F += 1.
/// The new quad joins exactly the subsets containing *both* adjacent faces.
public enum BevelEdges: MeshOp {
    public static let name = "Bevel"

    public struct Params: Sendable {
        /// Distance each endpoint slides along its adjacent face edges.
        public var width: Double
        public init(width: Double) { self.width = width }
    }

    public static func apply(_ mesh: HalfEdgeMesh, selection: ComponentSelection,
                             params: Params) throws -> MeshOpResult {
        guard case .edges(let edges) = selection, !edges.isEmpty else {
            throw MeshOpError.emptySelection
        }
        guard params.width > 0 else {
            throw MeshOpError.preconditionFailed("bevel width must be positive")
        }

        // Pairwise non-adjacency (v1): no two selected edges share a vertex.
        var seenVerts = Set<VertexID>()
        for e in edges.sorted(by: <) {
            for v in [e.a, e.b] {
                guard seenVerts.insert(v).inserted else {
                    throw MeshOpError.preconditionFailed(
                        "selected edges share vertex \(v.rawValue); adjacent edges are not supported in v1")
                }
            }
        }

        var out = mesh
        var newQuads = Set<FaceID>()

        // Edges are vertex-disjoint (checked above), but they may share flanking
        // faces — a corner's loop neighbor can be a vertex introduced by an
        // earlier bevel. So each edge is beveled against the *evolving* mesh:
        // adjacency, loops, and positions all read from `out`.
        for e in edges.sorted(by: <) {
            let edgeFaces = out.edgeFaceMap
            let vertexFaces = out.vertexFaceMap
            guard let adjacent = edgeFaces[e], !adjacent.isEmpty else {
                throw MeshOpError.unknownComponent("edge (\(e.a.rawValue),\(e.b.rawValue))")
            }
            guard adjacent.count == 2 else {
                throw MeshOpError.preconditionFailed(
                    "edge (\(e.a.rawValue),\(e.b.rawValue)) borders \(adjacent.count) face(s); bevel needs an interior manifold edge")
            }
            let f1 = adjacent[0], f2 = adjacent[1]

            // Per endpoint: third face, slide targets, and the new vertex pair.
            struct Corner {
                let third: FaceID
                let slide1: VertexID  // neighbor of v in f1 (≠ other endpoint)
                let slide2: VertexID  // neighbor of v in f2
                let new1: VertexID    // slides toward slide1
                let new2: VertexID    // slides toward slide2
            }
            var corners: [VertexID: Corner] = [:]

            for (v, other) in [(e.a, e.b), (e.b, e.a)] {
                let incident = vertexFaces[v] ?? []
                guard incident.count == 3 else {
                    throw MeshOpError.preconditionFailed(
                        "vertex \(v.rawValue) touches \(incident.count) face(s); bevel v1 requires face-valence exactly 3")
                }
                guard let third = incident.first(where: { $0 != f1 && $0 != f2 }) else {
                    throw MeshOpError.nonManifoldRegion(
                        "vertex \(v.rawValue) has no distinct third face beside the beveled edge")
                }

                func loopNeighbor(in face: FaceID) throws -> VertexID {
                    let loop = out.faceLoops[face]!
                    let i = loop.firstIndex(of: v)!
                    let prev = loop[(i + loop.count - 1) % loop.count]
                    let next = loop[(i + 1) % loop.count]
                    let candidate = prev == other ? next : prev
                    guard candidate != other else {
                        throw MeshOpError.preconditionFailed(
                            "face \(face.rawValue) is a degenerate wedge at edge (\(e.a.rawValue),\(e.b.rawValue))")
                    }
                    return candidate
                }
                let c1 = try loopNeighbor(in: f1)
                let c2 = try loopNeighbor(in: f2)

                // All incident edges must be interior (no boundary fans).
                for c in [other, c1, c2] where (edgeFaces[EdgeKey(v, c)]?.count ?? 0) != 2 {
                    throw MeshOpError.preconditionFailed(
                        "edge (\(v.rawValue),\(c.rawValue)) at the bevel corner is a boundary edge; bevel v1 requires a closed neighborhood")
                }

                let p = out.positions[v]!
                var slid: [VertexID: VertexID] = [:]
                for c in [c1, c2] {
                    let along = out.positions[c]! - p
                    let len = simd_length(along)
                    guard params.width < len - MeshInvariants.epsilon else {
                        throw MeshOpError.preconditionFailed(
                            "bevel width \(params.width) ≥ adjacent edge length \(len) at vertex \(v.rawValue); reduce the width")
                    }
                    slid[c] = out.addVertex(p + along / len * params.width)
                }
                corners[v] = Corner(third: third, slide1: c1, slide2: c2,
                                    new1: slid[c1]!, new2: slid[c2]!)
            }

            let ca = corners[e.a]!, cb = corners[e.b]!
            let preRetargetF1Loop = out.faceLoops[f1]!

            // Retarget the two adjacent faces onto the slid vertices.
            for (face, subs) in [(f1, (ca.new1, cb.new1)), (f2, (ca.new2, cb.new2))] {
                let loop = out.faceLoops[face]!
                out.replaceLoop(loop.map { $0 == e.a ? subs.0 : ($0 == e.b ? subs.1 : $0) },
                                for: face)
            }

            // Third faces: replace the corner vertex with its slid pair, ordered
            // so the vertex sliding toward next(v) comes last (keeps winding).
            for (v, corner) in [(e.a, ca), (e.b, cb)] {
                let loop = out.faceLoops[corner.third]!
                let i = loop.firstIndex(of: v)!
                let next = loop[(i + 1) % loop.count]
                let pair = next == corner.slide1
                    ? [corner.new2, corner.new1] : [corner.new1, corner.new2]
                var newLoop = loop
                newLoop.replaceSubrange(i...i, with: pair)
                out.replaceLoop(newLoop, for: corner.third)
            }

            // The bevel quad, wound opposite to f1's traversal of the old edge.
            let loop1 = preRetargetF1Loop
            let ia = loop1.firstIndex(of: e.a)!
            let f1TraversesAToB = loop1[(ia + 1) % loop1.count] == e.b
            let quadLoop = f1TraversesAToB
                ? [cb.new1, ca.new1, ca.new2, cb.new2]
                : [ca.new1, cb.new1, cb.new2, ca.new2]
            let quad = out.addFace(quadLoop)
            newQuads.insert(quad)
            // Invariant 6: the quad joins subsets shared by both flanking faces.
            for (name, members) in out.subsets where members.contains(f1) && members.contains(f2) {
                out.addFaceToSubset(quad, subset: name)
            }

            out.removeVertex(e.a)
            out.removeVertex(e.b)
        }

        let predicted = TopologyDelta(vertices: 2 * edges.count,
                                      edges: 3 * edges.count,
                                      faces: edges.count)
        try OpSupport.verify(before: mesh, after: out, predicted: predicted)
        return MeshOpResult(mesh: out, resultSelection: .faces(newQuads), delta: predicted)
    }
}
