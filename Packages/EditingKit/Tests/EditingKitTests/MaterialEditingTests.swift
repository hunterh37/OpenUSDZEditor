import Testing
import USDCore
@testable import EditingKit

// MARK: - Fixtures

private func materialPrim(
    _ path: String = "/Looks/Steel",
    attributes: [Attribute] = []
) -> Prim {
    Prim(path: PrimPath(path)!, typeName: "Material", attributes: attributes)
}

/// A UsdPreviewSurface shader prim, the shape real USD files author.
private func shaderPrim(
    _ path: String,
    id: AttributeValue = .token("UsdPreviewSurface"),
    attributes: [Attribute] = []
) -> Prim {
    Prim(path: PrimPath(path)!, typeName: "Shader",
         attributes: [Attribute(name: "info:id", value: id)] + attributes)
}

/// The real-file shape: a Material whose inputs live on a Shader child.
private func shaderBackedStage() -> StageSnapshot {
    let shader = shaderPrim("/Looks/Steel/Surface", attributes: [
        Attribute(name: "inputs:roughness", value: .double(0.5)),
    ])
    let steel = Prim(path: PrimPath("/Looks/Steel")!, typeName: "Material", children: [shader])
    let looks = Prim(path: PrimPath("/Looks")!, typeName: "Scope", children: [steel])
    let mesh = Prim(
        path: PrimPath("/Mesh")!, typeName: "Mesh",
        relationships: [Relationship(name: "material:binding", targets: [steel.path])])
    return StageSnapshot(rootPrims: [looks, mesh])
}

/// /Looks/Steel + a /Car hierarchy whose /Car/Body binds it by relationship.
private func boundStage() -> StageSnapshot {
    let steel = materialPrim(attributes: [
        Attribute(name: "inputs:roughness", value: .double(0.5)),
    ])
    let looks = Prim(path: PrimPath("/Looks")!, typeName: "Scope", children: [steel])
    let trim = Prim(path: PrimPath("/Car/Body/Trim")!, typeName: "Mesh")
    let body = Prim(
        path: PrimPath("/Car/Body")!, typeName: "Mesh",
        relationships: [Relationship(name: "material:binding", targets: [steel.path])],
        children: [trim])
    let car = Prim(path: PrimPath("/Car")!, typeName: "Xform", children: [body])
    return StageSnapshot(rootPrims: [looks, car])
}

@Suite("PreviewSurfaceInput")
struct PreviewSurfaceInputTests {

    @Test func catalogCoversTheUsdPreviewSurfaceInputSet() {
        let names = Set(PreviewSurfaceInput.catalog.map(\.name))
        #expect(names == [
            "diffuseColor", "emissiveColor", "useSpecularWorkflow", "specularColor",
            "metallic", "roughness", "clearcoat", "clearcoatRoughness",
            "opacity", "opacityThreshold", "ior", "normal", "displacement", "occlusion",
        ])
    }

    @Test func lookupAcceptsBareAndPrefixedNames() {
        #expect(PreviewSurfaceInput.named("roughness")?.name == "roughness")
        #expect(PreviewSurfaceInput.named("inputs:roughness")?.name == "roughness")
        #expect(PreviewSurfaceInput.named("inputs:nonsense") == nil)
    }

    @Test func attributeNameIsPrefixed() {
        #expect(PreviewSurfaceInput.named("metallic")?.attributeName == "inputs:metallic")
    }

    @Test func acceptsMatchingTypesOnly() throws {
        let metallic = try #require(PreviewSurfaceInput.named("metallic"))
        let diffuse = try #require(PreviewSurfaceInput.named("diffuseColor"))

        #expect(metallic.accepts(.double(0.5)))
        #expect(!metallic.accepts(.vector([1, 0, 0])))   // wrong type
        #expect(!metallic.accepts(.double(.nan)))        // non-finite
        #expect(diffuse.accepts(.vector([1, 0, 0])))
        #expect(!diffuse.accepts(.vector([1, 0])))       // wrong arity
        #expect(!diffuse.accepts(.double(1)))
    }

    @Test func choiceInputAcceptsOnlyItsOptions() throws {
        let workflow = try #require(PreviewSurfaceInput.named("useSpecularWorkflow"))
        #expect(workflow.accepts(.int(0)))
        #expect(workflow.accepts(.int(1)))
        #expect(!workflow.accepts(.int(2)))
    }

    @Test func clampingPullsScalarsIntoRange() throws {
        let metallic = try #require(PreviewSurfaceInput.named("metallic"))
        #expect(metallic.clamping(.double(1.4)) == .double(1.0))
        #expect(metallic.clamping(.double(-0.2)) == .double(0.0))
        #expect(metallic.clamping(.double(0.3)) == .double(0.3))
    }

    @Test func unboundedScalarIsNotClamped() throws {
        let displacement = try #require(PreviewSurfaceInput.named("displacement"))
        #expect(displacement.clamping(.double(42)) == .double(42))
        #expect(displacement.accepts(.double(-42)))
    }
}

@Suite("MaterialBinding")
struct MaterialBindingTests {

    @Test func resolvesRelationshipBinding() {
        let stage = boundStage()
        #expect(MaterialBinding.materialPath(for: PrimPath("/Car/Body")!, in: stage) == PrimPath("/Looks/Steel")!)
    }

    @Test func bindingIsInheritedDownNamespace() {
        // /Car/Body/Trim authors no binding; it inherits Body's.
        let stage = boundStage()
        #expect(MaterialBinding.materialPath(for: PrimPath("/Car/Body/Trim")!, in: stage) == PrimPath("/Looks/Steel")!)
    }

    @Test func closestBindingWins() {
        var stage = boundStage()
        let chrome = materialPrim("/Looks/Chrome")
        stage.rootPrims[0].children.append(chrome)
        // Override on the child.
        stage.rootPrims[1].children[0].children[0].relationships = [
            Relationship(name: "material:binding", targets: [chrome.path])
        ]
        #expect(MaterialBinding.materialPath(for: PrimPath("/Car/Body/Trim")!, in: stage) == chrome.path)
        #expect(MaterialBinding.materialPath(for: PrimPath("/Car/Body")!, in: stage) == PrimPath("/Looks/Steel")!)
    }

    @Test func materialPrimResolvesToItself() {
        let stage = boundStage()
        #expect(MaterialBinding.materialPath(for: PrimPath("/Looks/Steel")!, in: stage) == PrimPath("/Looks/Steel")!)
    }

    @Test func resolvesImporterMetadataBindingByName() {
        // USDAuthorStage spelling: a bare sanitized name in prim metadata.
        let steel = materialPrim()
        let looks = Prim(path: PrimPath("/Looks")!, typeName: "Scope", children: [steel])
        let mesh = Prim(path: PrimPath("/Mesh")!, typeName: "Mesh", metadata: ["material:binding": "Steel"])
        let stage = StageSnapshot(rootPrims: [looks, mesh])
        #expect(MaterialBinding.materialPath(for: mesh.path, in: stage) == steel.path)
    }

    @Test func metadataBindingIgnoresSameNamedNonMaterial() {
        // A decoy Xform named Steel must not shadow the real Material.
        let steel = materialPrim("/Looks/Steel")
        let looks = Prim(path: PrimPath("/Looks")!, typeName: "Scope", children: [steel])
        let decoy = Prim(path: PrimPath("/Steel")!, typeName: "Xform")
        let mesh = Prim(path: PrimPath("/Mesh")!, typeName: "Mesh", metadata: ["material:binding": "Steel"])
        let stage = StageSnapshot(rootPrims: [decoy, looks, mesh])
        #expect(MaterialBinding.materialPath(for: mesh.path, in: stage) == steel.path)
    }

    @Test func unboundPrimResolvesToNil() {
        let mesh = Prim(path: PrimPath("/Mesh")!, typeName: "Mesh")
        #expect(MaterialBinding.materialPath(for: mesh.path, in: StageSnapshot(rootPrims: [mesh])) == nil)
    }

    @Test func danglingBindingResolvesToNil() {
        let mesh = Prim(
            path: PrimPath("/Mesh")!, typeName: "Mesh",
            relationships: [Relationship(name: "material:binding", targets: [PrimPath("/Looks/Gone")!])])
        #expect(MaterialBinding.materialPath(for: mesh.path, in: StageSnapshot(rootPrims: [mesh])) == nil)
    }

    @Test func missingPrimResolvesToNil() {
        #expect(MaterialBinding.materialPath(for: PrimPath("/Nope")!, in: boundStage()) == nil)
    }

    // MARK: Surface resolution
    //
    // The distinction that matters: real files put `inputs:*` on a Shader child,
    // so editing must target that — authoring onto the Material prim instead is
    // silently inert in RealityKit.

    @Test func surfaceResolvesToPreviewSurfaceShaderChild() throws {
        let stage = shaderBackedStage()
        let resolved = try #require(MaterialBinding.resolve(for: PrimPath("/Mesh")!, in: stage))
        #expect(resolved.material.path == PrimPath("/Looks/Steel")!)
        #expect(resolved.surfacePath == PrimPath("/Looks/Steel/Surface")!)
        #expect(resolved.hasDedicatedShader)
        #expect(resolved.name == "Steel")
    }

    @Test func surfaceFallsBackToMaterialWhenInputsAreFlattened() throws {
        // The USDAuthorStage shape: inputs directly on the Material, no shader.
        let stage = boundStage()
        let resolved = try #require(MaterialBinding.resolve(for: PrimPath("/Car/Body")!, in: stage))
        #expect(resolved.surfacePath == resolved.material.path)
        #expect(!resolved.hasDedicatedShader)
    }

    @Test func nonPreviewSurfaceShaderIsNotTheSurface() {
        // A texture-reader shader child must not be mistaken for the surface.
        let reader = shaderPrim("/Looks/Steel/Tex", id: .token("UsdUVTexture"))
        let steel = Prim(path: PrimPath("/Looks/Steel")!, typeName: "Material", children: [reader])
        #expect(MaterialBinding.surfacePath(in: steel) == steel.path)
    }

    @Test func shaderIdToleratesStringTyping() {
        let shader = shaderPrim("/Looks/Steel/Surface", id: .string("UsdPreviewSurface"))
        let steel = Prim(path: PrimPath("/Looks/Steel")!, typeName: "Material", children: [shader])
        #expect(MaterialBinding.surfacePath(in: steel) == shader.path)
    }

    @Test func shaderWithoutIdIsNotTheSurface() {
        let shader = Prim(path: PrimPath("/Looks/Steel/Surface")!, typeName: "Shader")
        let steel = Prim(path: PrimPath("/Looks/Steel")!, typeName: "Material", children: [shader])
        #expect(MaterialBinding.surfacePath(in: steel) == steel.path)
    }

    @Test func selectingShaderResolvesToItsMaterial() throws {
        // Clicking the shader in the outliner should edit its material, not dead-end.
        let stage = shaderBackedStage()
        let resolved = try #require(MaterialBinding.resolve(for: PrimPath("/Looks/Steel/Surface")!, in: stage))
        #expect(resolved.material.path == PrimPath("/Looks/Steel")!)
        #expect(resolved.surfacePath == PrimPath("/Looks/Steel/Surface")!)
    }

    @Test func nestedShaderIsFound() {
        // Some writers nest the shader under a Scope inside the material.
        let shader = shaderPrim("/Looks/Steel/Net/Surface")
        let net = Prim(path: PrimPath("/Looks/Steel/Net")!, typeName: "Scope", children: [shader])
        let steel = Prim(path: PrimPath("/Looks/Steel")!, typeName: "Material", children: [net])
        #expect(MaterialBinding.surfacePath(in: steel) == shader.path)
    }
}

@Suite("SetMaterialInputCommand")
struct SetMaterialInputCommandTests {

    private let steelPath = PrimPath("/Looks/Steel")!

    /// Builds a command against the material bound in `stage`, resolved the same
    /// way the UI resolves it.
    private func make(_ name: String, _ value: AttributeValue, in stage: StageSnapshot) -> SetMaterialInputCommand? {
        guard let input = PreviewSurfaceInput.named(name),
              let material = MaterialBinding.resolve(for: steelPath, in: stage) else { return nil }
        return SetMaterialInputCommand.make(material, input: input, value: value, in: stage)
    }

    @Test func setsAuthoredInputAndUndoRestoresPriorValue() throws {
        let snapshot = boundStage()
        let stage = InMemoryStage(snapshot)
        let command = try #require(make("roughness", .double(0.1), in: snapshot))

        try command.execute(on: stage)
        #expect(stage.prim(at: steelPath)?.attribute(named: "inputs:roughness")?.value == .double(0.1))

        try command.undo(on: stage)
        #expect(stage.prim(at: steelPath)?.attribute(named: "inputs:roughness")?.value == .double(0.5))
    }

    @Test func undoRemovesPreviouslyUnauthoredInput() throws {
        // The regression this slice depends on: authoring a *new* input and
        // undoing must leave no opinion behind, not a fallback-valued one.
        let snapshot = boundStage()
        let stage = InMemoryStage(snapshot)
        let command = try #require(make("metallic", .double(1), in: snapshot))

        try command.execute(on: stage)
        #expect(stage.prim(at: steelPath)?.attribute(named: "inputs:metallic") != nil)

        try command.undo(on: stage)
        #expect(stage.prim(at: steelPath)?.attribute(named: "inputs:metallic") == nil)
    }

    @Test func clampsOutOfRangeValue() throws {
        let snapshot = boundStage()
        let command = try #require(make("metallic", .double(5), in: snapshot))
        #expect(command.newValue == .double(1))
    }

    @Test func rejectsWrongType() {
        #expect(make("metallic", .vector([1, 0, 0]), in: boundStage()) == nil)
    }

    @Test func rejectsSurfaceThatIsNotOnTheStage() throws {
        // A stale ResolvedMaterial (its prim deleted since resolution) must not
        // author onto a path that no longer exists.
        let stage = boundStage()
        let input = try #require(PreviewSurfaceInput.named("roughness"))
        let stale = ResolvedMaterial(
            material: Prim(path: PrimPath("/Looks/Gone")!, typeName: "Material"),
            surfacePath: PrimPath("/Looks/Gone")!)
        #expect(SetMaterialInputCommand.make(stale, input: input, value: .double(0.2), in: stage) == nil)
    }

    @Test func editsLandOnTheShaderNotTheMaterial() throws {
        // The regression that matters for real files: authoring onto the
        // Material prim when a shader owns the inputs is silently inert.
        let snapshot = shaderBackedStage()
        let stage = InMemoryStage(snapshot)
        let command = try #require(make("roughness", .double(0.9), in: snapshot))
        #expect(command.path == PrimPath("/Looks/Steel/Surface")!)

        try command.execute(on: stage)
        #expect(stage.prim(at: PrimPath("/Looks/Steel/Surface")!)?.attribute(named: "inputs:roughness")?.value
                == .double(0.9))
        // The Material prim itself stays clean.
        #expect(stage.prim(at: steelPath)?.attribute(named: "inputs:roughness") == nil)
    }

    @Test func labelNamesMaterialEvenWhenEditingShader() throws {
        // The user picked "Steel", not "Steel/Surface" — the undo menu should say so.
        let command = try #require(make("roughness", .double(0.9), in: shaderBackedStage()))
        #expect(command.label == "Set roughness on Steel")
    }

    @Test func unchangedValueIsNoCommand() {
        #expect(make("roughness", .double(0.5), in: boundStage()) == nil)
    }

    @Test func clampedNoOpIsRejected() {
        // 0.5 is already authored; an overshoot that clamps back onto it is a no-op.
        var snapshot = boundStage()
        snapshot.rootPrims[0].children[0].attributes = [Attribute(name: "inputs:metallic", value: .double(1))]
        #expect(make("metallic", .double(3), in: snapshot) == nil)
    }

    @Test func preservesAttributeQualifiers() throws {
        var snapshot = boundStage()
        snapshot.rootPrims[0].children[0].attributes = [
            Attribute(name: "inputs:roughness", value: .double(0.5),
                      isUniform: true, metadata: ["doc": "\"vendor\""]),
        ]
        let stage = InMemoryStage(snapshot)
        try #require(make("roughness", .double(0.2), in: snapshot)).execute(on: stage)

        let attr = try #require(stage.prim(at: steelPath)?.attribute(named: "inputs:roughness"))
        #expect(attr.isUniform)
        #expect(attr.metadata == ["doc": "\"vendor\""])
    }

    @Test func authoringOverAnimatedInputDropsTimeSamples() throws {
        var snapshot = boundStage()
        snapshot.rootPrims[0].children[0].attributes = [
            Attribute(name: "inputs:roughness", value: .double(0.5),
                      timeSamples: [TimeSample(time: 0, value: .double(0.1))]),
        ]
        let stage = InMemoryStage(snapshot)
        let command = try #require(make("roughness", .double(0.2), in: snapshot))
        try command.execute(on: stage)

        let attr = try #require(stage.prim(at: steelPath)?.attribute(named: "inputs:roughness"))
        #expect(attr.timeSamples == nil)
        #expect(attr.value == .double(0.2))

        // Undo restores the animation, not just the fallback value.
        try command.undo(on: stage)
        #expect(stage.prim(at: steelPath)?.attribute(named: "inputs:roughness")?.timeSamples?.count == 1)
    }

    @Test func labelNamesInputAndMaterial() throws {
        #expect(try #require(make("diffuseColor", .vector([1, 0, 0]), in: boundStage())).label
                == "Set diffuseColor on Steel")
    }

    @Test func colorRoundTrips() throws {
        let snapshot = boundStage()
        let stage = InMemoryStage(snapshot)
        let command = try #require(make("diffuseColor", .vector([0.9, 0.1, 0.1]), in: snapshot))
        try command.execute(on: stage)
        #expect(stage.prim(at: steelPath)?.attribute(named: "inputs:diffuseColor")?.value == .vector([0.9, 0.1, 0.1]))
        try command.undo(on: stage)
        #expect(stage.prim(at: steelPath)?.attribute(named: "inputs:diffuseColor") == nil)
    }
}

@Suite("removeAttribute mutation")
struct RemoveAttributeMutationTests {

    @Test func removesNamedAttribute() throws {
        let stage = InMemoryStage(boundStage())
        let path = PrimPath("/Looks/Steel")!
        try stage.apply(.removeAttribute(path: path, name: "inputs:roughness"))
        #expect(stage.prim(at: path)?.attributes.isEmpty == true)
    }

    @Test func absentAttributeIsTolerated() throws {
        let stage = InMemoryStage(boundStage())
        let path = PrimPath("/Looks/Steel")!
        try stage.apply(.removeAttribute(path: path, name: "inputs:nothingHere"))
        #expect(stage.prim(at: path)?.attributes.count == 1)
    }

    @Test func missingPrimThrows() {
        let stage = InMemoryStage(boundStage())
        #expect(throws: StageMutationError.self) {
            try stage.apply(.removeAttribute(path: PrimPath("/Nope")!, name: "inputs:roughness"))
        }
    }

    @Test func setAttributeCommandUndoRemovesNewlyAuthored() throws {
        let stage = InMemoryStage(boundStage())
        let path = PrimPath("/Looks/Steel")!
        let command = SetAttributeCommand(
            path: path,
            newAttribute: Attribute(name: "inputs:brandNew", value: .double(1)),
            oldAttribute: nil)
        try command.execute(on: stage)
        #expect(stage.prim(at: path)?.attribute(named: "inputs:brandNew") != nil)
        try command.undo(on: stage)
        #expect(stage.prim(at: path)?.attribute(named: "inputs:brandNew") == nil)
    }
}
