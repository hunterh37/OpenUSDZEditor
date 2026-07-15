import Testing
import Foundation
import USDCore
@testable import EditingKit

private func makeStage() -> InMemoryStage {
    // /Car
    //   /Body
    //   /Wheel  (2 attrs)
    let wheel = Prim(
        path: PrimPath("/Car/Wheel")!,
        typeName: "Mesh",
        attributes: [Attribute(name: "radius", value: .double(1.0))]
    )
    let body = Prim(path: PrimPath("/Car/Body")!, typeName: "Mesh")
    let car = Prim(path: PrimPath("/Car")!, typeName: "Xform", children: [body, wheel])
    return InMemoryStage(StageSnapshot(rootPrims: [car]))
}

@Suite("InMemoryStage mutations")
struct InMemoryStageTests {

    @Test func setVisibilityMutatesNestedPrim() throws {
        let stage = makeStage()
        try stage.apply(.setVisibility(path: PrimPath("/Car/Wheel")!, visibility: .invisible))
        #expect(stage.prim(at: PrimPath("/Car/Wheel")!)?.visibility == .invisible)
    }

    @Test func setActiveMutates() throws {
        let stage = makeStage()
        try stage.apply(.setActive(path: PrimPath("/Car/Body")!, isActive: false))
        #expect(stage.prim(at: PrimPath("/Car/Body")!)?.isActive == false)
    }

    @Test func setAttributeReplacesExisting() throws {
        let stage = makeStage()
        try stage.apply(.setAttribute(path: PrimPath("/Car/Wheel")!,
                                      attribute: Attribute(name: "radius", value: .double(2.5))))
        let attrs = stage.prim(at: PrimPath("/Car/Wheel")!)!.attributes
        #expect(attrs.count == 1)
        #expect(attrs.first?.value == .double(2.5))
    }

    @Test func renameCascadesToChildren() throws {
        let stage = makeStage()
        try stage.apply(.renamePrim(path: PrimPath("/Car")!, newName: "Truck"))
        #expect(stage.prim(at: PrimPath("/Truck")!) != nil)
        #expect(stage.prim(at: PrimPath("/Truck/Wheel")!) != nil)
        #expect(stage.prim(at: PrimPath("/Car")!) == nil)
    }

    @Test func renameRejectsSiblingCollision() throws {
        let stage = makeStage()
        #expect(throws: StageMutationError.self) {
            try stage.apply(.renamePrim(path: PrimPath("/Car/Wheel")!, newName: "Body"))
        }
    }

    @Test func removeThenInsertRoundTrips() throws {
        let stage = makeStage()
        let wheel = stage.prim(at: PrimPath("/Car/Wheel")!)!
        try stage.apply(.removePrim(path: PrimPath("/Car/Wheel")!))
        #expect(stage.prim(at: PrimPath("/Car/Wheel")!) == nil)
        try stage.apply(.insertPrim(parent: PrimPath("/Car")!, index: 1, prim: wheel))
        #expect(stage.prim(at: PrimPath("/Car/Wheel")!) != nil)
    }

    @Test func mutatingMissingPrimThrows() throws {
        let stage = makeStage()
        #expect(throws: StageMutationError.self) {
            try stage.apply(.setActive(path: PrimPath("/Nope")!, isActive: false))
        }
    }
}

@Suite("CommandStack undo/redo")
struct CommandStackTests {

    @Test func runRecordsUndoableCommand() throws {
        let stage = makeStage()
        let stack = CommandStack(stage: stage)
        #expect(!stack.canUndo)
        try stack.run(SetActiveCommand(path: PrimPath("/Car/Body")!, newValue: false, oldValue: true))
        #expect(stack.canUndo)
        #expect(stack.undoLabel == "Disable Body")
        #expect(stage.prim(at: PrimPath("/Car/Body")!)?.isActive == false)
    }

    @Test func undoRestoresPriorState() throws {
        let stage = makeStage()
        let stack = CommandStack(stage: stage)
        try stack.run(SetVisibilityCommand(path: PrimPath("/Car/Wheel")!, newVisibility: .invisible, oldVisibility: .inherited))
        try stack.undo()
        #expect(stage.prim(at: PrimPath("/Car/Wheel")!)?.visibility == .inherited)
        #expect(!stack.canUndo)
        #expect(stack.canRedo)
    }

    @Test func redoReappliesCommand() throws {
        let stage = makeStage()
        let stack = CommandStack(stage: stage)
        try stack.run(RenamePrimCommand(path: PrimPath("/Car")!, newName: "Truck"))
        try stack.undo()
        #expect(stage.prim(at: PrimPath("/Car")!) != nil)
        try stack.redo()
        #expect(stage.prim(at: PrimPath("/Truck")!) != nil)
    }

    @Test func removeCommandUndoRestoresPrim() throws {
        let stage = makeStage()
        let stack = CommandStack(stage: stage)
        let wheel = stage.prim(at: PrimPath("/Car/Wheel")!)!
        try stack.run(RemovePrimCommand(prim: wheel, parent: PrimPath("/Car")!, index: 1))
        #expect(stage.prim(at: PrimPath("/Car/Wheel")!) == nil)
        try stack.undo()
        let restored = stage.prim(at: PrimPath("/Car/Wheel")!)
        #expect(restored != nil)
        #expect(restored?.attributes.first?.name == "radius")
    }

    @Test func runningClearsRedoStack() throws {
        let stage = makeStage()
        let stack = CommandStack(stage: stage)
        try stack.run(SetActiveCommand(path: PrimPath("/Car/Body")!, newValue: false, oldValue: true))
        try stack.undo()
        #expect(stack.canRedo)
        try stack.run(SetActiveCommand(path: PrimPath("/Car/Wheel")!, newValue: false, oldValue: true))
        #expect(!stack.canRedo)
    }

    @Test func compositeCommandUndoesAsOneUnit() throws {
        let stage = makeStage()
        let stack = CommandStack(stage: stage)
        let composite = CompositeCommand(label: "Disable both", commands: [
            SetActiveCommand(path: PrimPath("/Car/Body")!, newValue: false, oldValue: true),
            SetActiveCommand(path: PrimPath("/Car/Wheel")!, newValue: false, oldValue: true),
        ])
        try stack.run(composite)
        #expect(stage.prim(at: PrimPath("/Car/Body")!)?.isActive == false)
        #expect(stage.prim(at: PrimPath("/Car/Wheel")!)?.isActive == false)
        #expect(stack.undoCount == 1)
        try stack.undo()
        #expect(stage.prim(at: PrimPath("/Car/Body")!)?.isActive == true)
        #expect(stage.prim(at: PrimPath("/Car/Wheel")!)?.isActive == true)
    }
}

@Suite("UndoManagerBridge")
@MainActor
struct UndoManagerBridgeTests {

    @Test func undoManagerDrivesStack() throws {
        let stage = makeStage()
        let stack = CommandStack(stage: stage)
        let manager = UndoManager()
        manager.groupsByEvent = false
        let bridge = UndoManagerBridge(stack: stack, undoManager: manager)

        // No run loop in tests, so open the group the app would get per event.
        manager.beginUndoGrouping()
        try bridge.run(SetVisibilityCommand(path: PrimPath("/Car/Wheel")!, newVisibility: .invisible, oldVisibility: .inherited))
        manager.endUndoGrouping()
        #expect(manager.canUndo)
        #expect(manager.undoActionName == "Hide Wheel")

        manager.undo()
        #expect(stage.prim(at: PrimPath("/Car/Wheel")!)?.visibility == .inherited)
        #expect(manager.canRedo)

        manager.redo()
        #expect(stage.prim(at: PrimPath("/Car/Wheel")!)?.visibility == .invisible)
    }
}
