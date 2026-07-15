import Testing
import Foundation
import USDCore
@testable import EditingKit

/// Records applied mutations; no real stage needed to verify command logic.
final class RecordingStage: USDStageMutable, @unchecked Sendable {
    var sourceURL: URL? { nil }
    var metadata = StageMetadata()
    var rootPrims: [Prim] = []
    private(set) var applied: [StageMutation] = []

    func apply(_ mutation: StageMutation) throws {
        applied.append(mutation)
    }
}

@Suite("SetVariantSelectionCommand")
struct SetVariantSelectionCommandTests {

    let path = PrimPath("/Car")!

    @Test func executeAndUndoFlipSelection() throws {
        let stage = RecordingStage()
        let command = SetVariantSelectionCommand(path: path, setName: "color", newSelection: "blue", oldSelection: "red")
        try command.execute(on: stage)
        try command.undo(on: stage)
        #expect(stage.applied == [
            .setVariantSelection(path: path, setName: "color", selection: "blue"),
            .setVariantSelection(path: path, setName: "color", selection: "red"),
        ])
    }

    @Test func labelNamesSetAndSelection() {
        #expect(SetVariantSelectionCommand(path: path, setName: "color", newSelection: "blue", oldSelection: "red").label == "Set color to blue")
        #expect(SetVariantSelectionCommand(path: path, setName: "color", newSelection: nil, oldSelection: "red").label == "Set color to none")
    }

    @Test func appliesAgainstInMemoryStage() throws {
        let car = Prim(path: path, typeName: "Xform",
                       variantSets: [VariantSet(name: "color", variants: ["red", "blue"], selection: "red")])
        let stage = InMemoryStage(StageSnapshot(rootPrims: [car]))
        let command = SetVariantSelectionCommand(path: path, setName: "color", newSelection: "blue", oldSelection: "red")

        try command.execute(on: stage)
        #expect(stage.rootPrims[0].variantSets[0].selection == "blue")
        try command.undo(on: stage)
        #expect(stage.rootPrims[0].variantSets[0].selection == "red")
    }

    @Test func unknownVariantSetThrows() {
        let car = Prim(path: path, typeName: "Xform")
        let stage = InMemoryStage(StageSnapshot(rootPrims: [car]))
        let command = SetVariantSelectionCommand(path: path, setName: "ghost", newSelection: "x", oldSelection: nil)
        #expect(throws: StageMutationError.self) { try command.execute(on: stage) }
    }
}

@Suite("SetVisibilityCommand")
struct SetVisibilityCommandTests {

    let path = PrimPath("/Car/Wheel")!

    @Test func executeAppliesNewVisibility() throws {
        let stage = RecordingStage()
        let command = SetVisibilityCommand(path: path, newVisibility: .invisible, oldVisibility: .inherited)
        try command.execute(on: stage)
        #expect(stage.applied == [.setVisibility(path: path, visibility: .invisible)])
    }

    @Test func undoRestoresOldVisibility() throws {
        let stage = RecordingStage()
        let command = SetVisibilityCommand(path: path, newVisibility: .invisible, oldVisibility: .inherited)
        try command.execute(on: stage)
        try command.undo(on: stage)
        #expect(stage.applied.last == .setVisibility(path: path, visibility: .inherited))
    }

    @Test func labelsNameThePart() {
        #expect(SetVisibilityCommand(path: path, newVisibility: .invisible, oldVisibility: .inherited).label == "Hide Wheel")
        #expect(SetVisibilityCommand(path: path, newVisibility: .inherited, oldVisibility: .invisible).label == "Show Wheel")
    }
}
