#if canImport(Foundation)
import Foundation
import USDCore

/// Bridges a `CommandStack` to AppKit's `NSUndoManager`, so the app's Edit menu,
/// ⌘Z / ⇧⌘Z, and `NSDocument` dirty-tracking drive the stack without either
/// side depending on the other.
///
/// The bridge uses the canonical "ping-pong" registration pattern: running a
/// command registers an undo block; when the undo manager invokes it (an undo),
/// that block registers a redo block, and vice-versa. Action names propagate to
/// the menu ("Undo Rename Wheel").
///
/// All calls must occur on the main thread, per `NSUndoManager`.
@MainActor
public final class UndoManagerBridge {
    public let stack: CommandStack
    private let undoManager: UndoManager

    public init(stack: CommandStack, undoManager: UndoManager) {
        self.stack = stack
        self.undoManager = undoManager
    }

    /// Runs `command` through the stack and registers a matching undo with the
    /// `NSUndoManager`.
    @discardableResult
    public func run(_ command: any EditCommand) throws -> String {
        let label = try stack.run(command)
        registerUndo(label: label)
        return label
    }

    private func registerUndo(label: String) {
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                try? target.stack.undo()
                target.registerRedo(label: label)
            }
        }
        undoManager.setActionName(label)
    }

    private func registerRedo(label: String) {
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                try? target.stack.redo()
                target.registerUndo(label: label)
            }
        }
        undoManager.setActionName(label)
    }
}
#endif
