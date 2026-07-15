import Foundation
import USDCore

/// The editor's undo/redo command layer.
///
/// Every mutation the user makes flows through `run(_:)`, which executes the
/// command against the stage and pushes it onto the undo stack. `undo()` and
/// `redo()` replay a command's inverse or re-apply. Running a fresh command
/// clears the redo stack, matching standard editor semantics.
///
/// The stack is UI-agnostic; `UndoManagerBridge` wires it to AppKit's
/// `NSUndoManager` so the app's Edit menu, ⌘Z/⇧⌘Z, and document dirty-state all
/// work without the stack knowing anything about AppKit.
public final class CommandStack: @unchecked Sendable {
    private let stage: any USDStageMutable
    private var undoStack: [any EditCommand] = []
    private var redoStack: [any EditCommand] = []
    private let lock = NSLock()

    /// Called after any change to the stack (run/undo/redo). Use it to refresh
    /// the viewport and menu-item enablement.
    public var onChange: (@Sendable () -> Void)?

    public init(stage: any USDStageMutable) {
        self.stage = stage
    }

    public var canUndo: Bool { lock.withLock { !undoStack.isEmpty } }
    public var canRedo: Bool { lock.withLock { !redoStack.isEmpty } }

    /// Label of the command that would be undone, e.g. "Rename Wheel".
    public var undoLabel: String? { lock.withLock { undoStack.last?.label } }
    /// Label of the command that would be redone.
    public var redoLabel: String? { lock.withLock { redoStack.last?.label } }

    /// Depth of the undo history (for tests / telemetry).
    public var undoCount: Int { lock.withLock { undoStack.count } }

    /// Executes `command` and records it for undo, clearing the redo stack.
    @discardableResult
    public func run(_ command: any EditCommand) throws -> String {
        try command.execute(on: stage)
        lock.withLock {
            undoStack.append(command)
            redoStack.removeAll()
        }
        onChange?()
        return command.label
    }

    /// Reverts the most recent command. Returns its label, or `nil` if empty.
    @discardableResult
    public func undo() throws -> String? {
        guard let command = lock.withLock({ undoStack.popLast() }) else { return nil }
        try command.undo(on: stage)
        lock.withLock { redoStack.append(command) }
        onChange?()
        return command.label
    }

    /// Re-applies the most recently undone command. Returns its label, or `nil`.
    @discardableResult
    public func redo() throws -> String? {
        guard let command = lock.withLock({ redoStack.popLast() }) else { return nil }
        try command.execute(on: stage)
        lock.withLock { undoStack.append(command) }
        onChange?()
        return command.label
    }

    /// Clears all history — e.g. after Save flattens the layer or on document close.
    public func clear() {
        lock.withLock {
            undoStack.removeAll()
            redoStack.removeAll()
        }
        onChange?()
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock(); defer { unlock() }
        return try body()
    }
}
