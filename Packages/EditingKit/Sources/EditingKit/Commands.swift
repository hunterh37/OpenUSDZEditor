import USDCore

/// Activate / deactivate a prim (PRD §5.3 "Disable" — the prim is pruned from
/// the composed stage but preserved in the file).
public struct SetActiveCommand: EditCommand {
    public let path: PrimPath
    public let newValue: Bool
    public let oldValue: Bool

    public init(path: PrimPath, newValue: Bool, oldValue: Bool) {
        self.path = path
        self.newValue = newValue
        self.oldValue = oldValue
    }

    public var label: String {
        newValue ? "Enable \(path.name)" : "Disable \(path.name)"
    }

    public func execute(on stage: any USDStageMutable) throws {
        try stage.apply(.setActive(path: path, isActive: newValue))
    }

    public func undo(on stage: any USDStageMutable) throws {
        try stage.apply(.setActive(path: path, isActive: oldValue))
    }
}

/// Rename a prim in place. Undo renames back using the *new* path, which is the
/// prim's location after execution.
public struct RenamePrimCommand: EditCommand {
    public let path: PrimPath
    public let newName: String
    public let oldName: String

    public init(path: PrimPath, newName: String) {
        self.path = path
        self.newName = newName
        self.oldName = path.name
    }

    /// The prim's path after a successful rename.
    public var renamedPath: PrimPath {
        path.parent.appending(newName) ?? path
    }

    public var label: String { "Rename \(oldName) to \(newName)" }

    public func execute(on stage: any USDStageMutable) throws {
        try stage.apply(.renamePrim(path: path, newName: newName))
    }

    public func undo(on stage: any USDStageMutable) throws {
        try stage.apply(.renamePrim(path: renamedPath, newName: oldName))
    }
}

/// Delete a prim (and its subtree). The removed snapshot is captured so undo can
/// re-insert it at its original sibling index.
public struct RemovePrimCommand: EditCommand {
    public let removed: Prim
    public let parent: PrimPath?
    public let index: Int

    /// - Parameters:
    ///   - prim: the prim snapshot being removed (captured for undo).
    ///   - parent: the parent path, or `nil` for a root prim.
    ///   - index: the prim's index among its siblings, restored on undo.
    public init(prim: Prim, parent: PrimPath?, index: Int) {
        self.removed = prim
        self.parent = parent
        self.index = index
    }

    public var label: String { "Delete \(removed.name)" }

    public func execute(on stage: any USDStageMutable) throws {
        try stage.apply(.removePrim(path: removed.path))
    }

    public func undo(on stage: any USDStageMutable) throws {
        try stage.apply(.insertPrim(parent: parent, index: index, prim: removed))
    }
}

/// Author (or replace) a single attribute on a prim.
public struct SetAttributeCommand: EditCommand {
    public let path: PrimPath
    public let newAttribute: Attribute
    /// The prior attribute, or `nil` when the attribute did not exist before.
    public let oldAttribute: Attribute?

    public init(path: PrimPath, newAttribute: Attribute, oldAttribute: Attribute?) {
        self.path = path
        self.newAttribute = newAttribute
        self.oldAttribute = oldAttribute
    }

    public var label: String { "Set \(newAttribute.name)" }

    public func execute(on stage: any USDStageMutable) throws {
        try stage.apply(.setAttribute(path: path, attribute: newAttribute))
    }

    public func undo(on stage: any USDStageMutable) throws {
        if let oldAttribute {
            try stage.apply(.setAttribute(path: path, attribute: oldAttribute))
        }
        // NB: when the attribute was newly authored there is no removeAttribute
        // mutation yet; undo is a no-op until that vocabulary lands (Phase 3).
    }
}

/// Groups several commands into one undoable unit — the seam gizmo drags use to
/// coalesce a stream of transform edits into a single Edit ▸ Undo entry.
public struct CompositeCommand: EditCommand {
    public let label: String
    public let commands: [any EditCommand]

    public init(label: String, commands: [any EditCommand]) {
        self.label = label
        self.commands = commands
    }

    public func execute(on stage: any USDStageMutable) throws {
        for command in commands {
            try command.execute(on: stage)
        }
    }

    public func undo(on stage: any USDStageMutable) throws {
        for command in commands.reversed() {
            try command.undo(on: stage)
        }
    }
}
