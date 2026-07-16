import AppKit
import SwiftUI

/// Offscreen rendering of real editor views to PNG.
///
/// **Nothing here may touch the user's screen.** Two guarantees combine:
/// `NSApplication.setActivationPolicy(.prohibited)` keeps the process out of the
/// Dock and out of the window server's front-most rotation, and the window we
/// render into is never ordered front — no `makeKeyAndOrderFront`, no
/// `NSApp.activate`, `isVisible` stays false. It exists purely to give AppKit a
/// view hierarchy to lay out.
///
/// Why a window rather than SwiftUI's `ImageRenderer`: the inspector is built
/// from AppKit-backed controls (segmented `Picker`, `ColorPicker`, `Slider`).
/// `ImageRenderer` can't rasterise those — it emits a yellow "unsupported"
/// placeholder and drops the content. `NSHostingView` in an offscreen window
/// renders them for real, because they're in a real (just invisible) hierarchy.
@MainActor
enum Render {

    /// Puts the process in a state where it can host AppKit-backed SwiftUI
    /// controls without appearing anywhere. Idempotent.
    static func prepareHeadless() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
    }

    /// Rasterises `view` at `size` to a PNG on disk.
    static func png(_ view: some View, size: CGSize, to url: URL) throws {
        prepareHeadless()

        let hosting = NSHostingView(rootView: AnyView(view.frame(width: size.width, height: size.height)))
        hosting.frame = CGRect(origin: .zero, size: size)

        // Borderless + never shown. The window is a layout host, not a UI.
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.contentView = hosting
        // The app ships dark chrome; without this the capture wouldn't match.
        window.appearance = NSAppearance(named: .darkAqua)
        // NSWindow defaults this to true for programmatically-created windows:
        // close() would hand AppKit a release that ARC also performs, and the
        // second shot of a scenario segfaults on the over-released window.
        window.isReleasedWhenClosed = false

        // SwiftUI lays out and resolves @Observable reads on the run loop, so a
        // capture taken synchronously after construction comes back empty. Spin
        // briefly, then force layout before reading pixels.
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw HarnessError.renderFailed(url.lastPathComponent)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw HarnessError.renderFailed(url.lastPathComponent)
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)

        // Release the host explicitly; a scenario takes many shots and each one
        // otherwise keeps a window (and its backing store) alive to process exit.
        window.contentView = nil
        window.close()
    }
}
