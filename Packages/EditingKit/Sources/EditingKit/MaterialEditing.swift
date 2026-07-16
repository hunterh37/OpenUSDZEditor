import USDCore

/// UsdPreviewSurface editing — the material half of Phase 3 (PRD §5.3,
/// specs/editing-model.md `SetMaterialInputCommand`).
///
/// Three pieces live here:
///
/// 1. ``PreviewSurfaceInput`` — the closed catalog of shader inputs RealityKit
///    honours, with the type and fallback USD declares for each. Editing is
///    deliberately gated on this catalog (mutation rule 0: author only what
///    RealityKit renders) rather than exposing arbitrary `inputs:*` strings.
/// 2. ``MaterialBinding`` — resolves "what material does this mesh use, and
///    where do its inputs actually live?" across the shapes the bridge and
///    importers produce.
/// 3. ``SetMaterialInputCommand`` — the undoable set.

// MARK: - Input catalog

/// One editable UsdPreviewSurface input.
public struct PreviewSurfaceInput: Hashable, Sendable, Identifiable {

    /// How the inspector should render an input — and what a legal value is.
    public enum Kind: Hashable, Sendable {
        /// `color3f`, authored as a 3-component `.vector`.
        case color
        /// `float`, with the range USD constrains it to (`nil` = unbounded).
        case scalar(ClosedRange<Double>?)
        /// `normal3f`, authored as a 3-component `.vector`.
        case normal
        /// `int` with a fixed set of legal values.
        case choice([Int])
    }

    /// The input name *without* the `inputs:` prefix, e.g. `diffuseColor`.
    public let name: String
    public let kind: Kind
    /// The value USD falls back to when no opinion is authored. Also what the
    /// inspector shows for an unauthored input.
    public let fallback: AttributeValue
    /// Short inspector help text.
    public let summary: String

    public var id: String { name }

    /// The attribute name as authored on the prim.
    public var attributeName: String { "inputs:\(name)" }

    public init(name: String, kind: Kind, fallback: AttributeValue, summary: String) {
        self.name = name
        self.kind = kind
        self.fallback = fallback
        self.summary = summary
    }

    /// `true` when `value` matches this input's declared type and range — the
    /// gate every command runs through, so a bad UI or script value is rejected
    /// before it reaches the stage.
    public func accepts(_ value: AttributeValue) -> Bool {
        switch (kind, value) {
        case let (.color, .vector(v)), let (.normal, .vector(v)):
            return v.count == 3
        case let (.scalar(range), .double(d)):
            guard d.isFinite else { return false }
            return range.map { $0.contains(d) } ?? true
        case let (.choice(options), .int(i)):
            return options.contains(i)
        default:
            return false
        }
    }

    /// Clamps `value` into the input's legal range where that is meaningful,
    /// so a slider or script overshoot lands on the nearest valid value rather
    /// than being dropped.
    public func clamping(_ value: AttributeValue) -> AttributeValue {
        guard case let .scalar(range) = kind, case let .double(d) = value,
              let range, d.isFinite else { return value }
        return .double(min(max(d, range.lowerBound), range.upperBound))
    }
}

extension PreviewSurfaceInput {

    /// The full UsdPreviewSurface input set, in inspector display order.
    public static let catalog: [PreviewSurfaceInput] = [
        .init(name: "diffuseColor", kind: .color, fallback: .vector([0.18, 0.18, 0.18]),
              summary: "Base albedo colour."),
        .init(name: "emissiveColor", kind: .color, fallback: .vector([0, 0, 0]),
              summary: "Light emitted by the surface."),
        .init(name: "useSpecularWorkflow", kind: .choice([0, 1]), fallback: .int(0),
              summary: "0 = metallic workflow, 1 = specular workflow."),
        .init(name: "specularColor", kind: .color, fallback: .vector([0, 0, 0]),
              summary: "Specular tint (specular workflow only)."),
        .init(name: "metallic", kind: .scalar(0...1), fallback: .double(0),
              summary: "0 = dielectric, 1 = metal."),
        .init(name: "roughness", kind: .scalar(0...1), fallback: .double(0.5),
              summary: "0 = mirror, 1 = fully diffuse."),
        .init(name: "clearcoat", kind: .scalar(0...1), fallback: .double(0),
              summary: "Strength of the clearcoat lobe."),
        .init(name: "clearcoatRoughness", kind: .scalar(0...1), fallback: .double(0.01),
              summary: "Roughness of the clearcoat lobe."),
        .init(name: "opacity", kind: .scalar(0...1), fallback: .double(1),
              summary: "1 = opaque, 0 = fully transparent."),
        .init(name: "opacityThreshold", kind: .scalar(0...1), fallback: .double(0),
              summary: "Above 0, opacity becomes a cutout mask."),
        .init(name: "ior", kind: .scalar(1...3), fallback: .double(1.5),
              summary: "Index of refraction."),
        .init(name: "normal", kind: .normal, fallback: .vector([0, 0, 1]),
              summary: "Tangent-space normal."),
        .init(name: "displacement", kind: .scalar(nil), fallback: .double(0),
              summary: "Displacement along the normal."),
        .init(name: "occlusion", kind: .scalar(0...1), fallback: .double(1),
              summary: "Ambient occlusion multiplier."),
    ]

    /// Looks up a catalog entry by bare name (`roughness`) or authored attribute
    /// name (`inputs:roughness`).
    public static func named(_ name: String) -> PreviewSurfaceInput? {
        let bare = name.hasPrefix("inputs:") ? String(name.dropFirst("inputs:".count)) : name
        return catalog.first { $0.name == bare }
    }
}

// MARK: - Binding resolution

/// A material resolved for editing: the Material prim itself, plus the prim its
/// UsdPreviewSurface inputs actually live on.
///
/// These are usually **not the same prim**. A real USD file authors a Material
/// with a `Shader` child (`info:id = "UsdPreviewSurface"`) that carries the
/// `inputs:*`; the Material only routes it via `outputs:surface`. Authoring
/// `inputs:diffuseColor` onto the Material prim in that shape is silently
/// inert — RealityKit renders the shader's opinion, not the Material's. So the
/// editing surface is resolved once, here, and commands target ``surfacePath``.
public struct ResolvedMaterial: Hashable, Sendable {
    /// The bound Material prim — the user-facing identity ("Paint").
    public let material: Prim
    /// The prim carrying the surface's `inputs:*`: the UsdPreviewSurface shader
    /// child, or the Material itself in the flattened shape `USDAuthorStage`
    /// writes.
    public let surfacePath: PrimPath

    public init(material: Prim, surfacePath: PrimPath) {
        self.material = material
        self.surfacePath = surfacePath
    }

    /// The material's name, for undo labels and inspector chrome.
    public var name: String { material.path.name }

    /// `true` when the inputs live on a separate shader prim.
    public var hasDedicatedShader: Bool { surfacePath != material.path }
}

/// Resolves the material bound to a prim, and the surface prim to edit.
///
/// UsdShade binds materials with a `material:binding` relationship that is
/// *inherited down namespace* — a binding on `/Car` applies to `/Car/Body/Trim`
/// unless something closer overrides it. Two spellings reach us in practice: the
/// bridge surfaces a real `Relationship`, while `USDAuthorStage` records the
/// target as a bare sanitized name in `metadata["material:binding"]`. Both are
/// resolved here so the inspector doesn't care which importer produced the file.
public enum MaterialBinding {

    /// The relationship/metadata key UsdShade uses.
    public static let key = "material:binding"

    /// The `info:id` identifying a UsdPreviewSurface shader.
    public static let previewSurfaceID = "UsdPreviewSurface"

    /// The material bound to `path` plus its editable surface prim, walking up
    /// the namespace to honour inherited bindings. Resolves a Material prim (or
    /// a shader inside one) to itself. `nil` when nothing in the ancestor chain
    /// binds a resolvable material.
    public static func resolve(for path: PrimPath, in stage: any USDStageProtocol) -> ResolvedMaterial? {
        materialPath(for: path, in: stage)
            .flatMap { stage.prim(at: $0) }
            .map { ResolvedMaterial(material: $0, surfacePath: surfacePath(in: $0)) }
    }

    /// The path of the material bound to `path`, walking up the namespace to
    /// honour inherited bindings. Returns `path` itself when it *is* a Material,
    /// and the enclosing Material when `path` is a shader inside one — selecting
    /// a shader in the outliner should edit its material, not dead-end.
    /// `nil` when nothing in the ancestor chain binds a resolvable material.
    public static func materialPath(for path: PrimPath, in stage: any USDStageProtocol) -> PrimPath? {
        guard stage.prim(at: path) != nil else { return nil }

        var current: PrimPath? = path
        while let candidate = current, let prim = stage.prim(at: candidate) {
            // The prim itself (or an ancestor of it) being a Material wins: a
            // shader's inputs belong to the material enclosing it.
            if prim.typeName == "Material" { return prim.path }
            if let resolved = directBinding(of: prim, in: stage) { return resolved }
            current = candidate.isRoot ? nil : candidate.parent
        }
        return nil
    }

    /// The material prim bound to `path`, resolved as in ``materialPath(for:in:)``.
    public static func material(for path: PrimPath, in stage: any USDStageProtocol) -> Prim? {
        materialPath(for: path, in: stage).flatMap { stage.prim(at: $0) }
    }

    /// The prim inside `material` whose `inputs:*` drive the surface.
    ///
    /// Prefers a `UsdPreviewSurface` shader in the material's subtree (the shape
    /// real files use). Falls back to the Material prim itself — which is both
    /// the flattened shape `USDAuthorStage` writes and the only sane target for
    /// a material with no shader at all, where authoring an input at least
    /// records the user's intent rather than dropping it.
    ///
    /// - Note: `outputs:surface` connections aren't modelled in the snapshot
    ///   yet, so a material with several preview surfaces resolves to the first
    ///   in depth-first order rather than the connected one.
    public static func surfacePath(in material: Prim) -> PrimPath {
        if let shader = material.flattened().first(where: isPreviewSurface) {
            return shader.path
        }
        return material.path
    }

    /// `true` when `prim` is a UsdPreviewSurface shader.
    private static func isPreviewSurface(_ prim: Prim) -> Bool {
        guard prim.typeName == "Shader" else { return false }
        switch prim.attribute(named: "info:id")?.value {
        // usd-core types `info:id` as a token; tolerate `string` from looser writers.
        case .token(previewSurfaceID), .string(previewSurfaceID): return true
        default: return false
        }
    }

    /// The binding authored *directly* on `prim` (no ancestor walk), resolved to
    /// a real Material prim on the stage.
    private static func directBinding(of prim: Prim, in stage: any USDStageProtocol) -> PrimPath? {
        if let relationship = prim.relationships.first(where: { $0.name == key }),
           let target = relationship.targets.first,
           isMaterial(at: target, in: stage) {
            return target
        }
        // Importer spelling: a bare material name in prim metadata. Resolve it
        // against Material prims only, so a same-named Xform can't shadow it.
        if let name = prim.metadata[key] {
            if let absolute = PrimPath(name), isMaterial(at: absolute, in: stage) {
                return absolute
            }
            if let match = stage.allPrims().first(where: { $0.typeName == "Material" && $0.name == name }) {
                return match.path
            }
        }
        return nil
    }

    private static func isMaterial(at path: PrimPath, in stage: any USDStageProtocol) -> Bool {
        stage.prim(at: path)?.typeName == "Material"
    }
}

// MARK: - Command

/// Sets one UsdPreviewSurface input on a material's surface prim, undoably.
///
/// Wraps `setAttribute` with three things the generic attribute command can't
/// know: which prim actually carries the surface's inputs (see
/// ``ResolvedMaterial``), the input's declared type (so an illegal value never
/// reaches the stage), and a label naming the material the user thinks they're
/// editing rather than the shader prim underneath it. Undo restores the prior
/// opinion — or removes the attribute entirely when the input was previously
/// unauthored.
public struct SetMaterialInputCommand: EditCommand {
    /// The surface prim being edited — a shader child, or the material itself.
    public let path: PrimPath
    public let input: PreviewSurfaceInput
    public let newValue: AttributeValue
    /// The prior attribute, or `nil` when the input carried no opinion.
    public let oldAttribute: Attribute?
    /// The material's name, for the undo label.
    public let materialName: String

    /// Builds the command, or `nil` when the edit is illegal or a no-op.
    ///
    /// Takes a ``ResolvedMaterial`` rather than a loose path so a caller can't
    /// aim an input at the Material prim when a shader child owns it.
    ///
    /// - Parameters:
    ///   - material: the resolved material, from ``MaterialBinding/resolve(for:in:)``.
    ///   - input: the catalog entry being set.
    ///   - value: the new value; clamped into the input's range, then rejected
    ///     if it still doesn't match the declared type.
    public static func make(
        _ material: ResolvedMaterial,
        input: PreviewSurfaceInput,
        value: AttributeValue,
        in stage: any USDStageProtocol
    ) -> SetMaterialInputCommand? {
        guard let surface = stage.prim(at: material.surfacePath) else { return nil }
        let clamped = input.clamping(value)
        guard input.accepts(clamped) else { return nil }

        let old = surface.attribute(named: input.attributeName)
        // No-op guard: same value, and not a re-author of an animated attribute.
        if let old, old.value == clamped, old.timeSamples == nil { return nil }

        return SetMaterialInputCommand(
            path: material.surfacePath, input: input, newValue: clamped,
            oldAttribute: old, materialName: material.name)
    }

    public init(
        path: PrimPath,
        input: PreviewSurfaceInput,
        newValue: AttributeValue,
        oldAttribute: Attribute?,
        materialName: String
    ) {
        self.path = path
        self.input = input
        self.newValue = newValue
        self.oldAttribute = oldAttribute
        self.materialName = materialName
    }

    public var label: String { "Set \(input.name) on \(materialName)" }

    /// The attribute this command authors. Preserves the prior attribute's
    /// qualifiers (`uniform`, metadata) so setting a value doesn't quietly drop
    /// them; time samples are dropped deliberately — authoring a static value
    /// over an animated input is what the user asked for.
    private var newAttribute: Attribute {
        Attribute(
            name: input.attributeName,
            value: newValue,
            isUniform: oldAttribute?.isUniform ?? false,
            metadata: oldAttribute?.metadata ?? [:])
    }

    public func execute(on stage: any USDStageMutable) throws {
        try stage.apply(.setAttribute(path: path, attribute: newAttribute))
    }

    public func undo(on stage: any USDStageMutable) throws {
        if let oldAttribute {
            try stage.apply(.setAttribute(path: path, attribute: oldAttribute))
        } else {
            try stage.apply(.removeAttribute(path: path, name: input.attributeName))
        }
    }
}
