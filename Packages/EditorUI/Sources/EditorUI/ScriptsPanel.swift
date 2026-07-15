import SwiftUI
import UniformTypeIdentifiers
import ScriptingKit
import DicyaninDesignSystem

/// Script library panel (Phase 4 seam). Lists bundled starter scripts plus any
/// the user adds; the embedded Python console that actually runs them arrives
/// with ScriptingKit's REPL. For now selecting a script previews its source.
struct ScriptsPanel: View {
    let onClose: () -> Void

    @State private var entries: [ScriptEntry] = []
    @State private var selected: ScriptEntry?
    @State private var source: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Palette.panelBorder.color)
            HSplitView {
                list.frame(minWidth: 180, idealWidth: 220)
                preview.frame(minWidth: 260, maxWidth: .infinity)
            }
        }
        .frame(width: 640, height: 460)
        .background(Palette.windowBackground.color)
        .onAppear(perform: reload)
    }

    private var header: some View {
        HStack {
            Text("Scripts")
                .font(.system(size: TypeScale.title, weight: .semibold))
                .foregroundStyle(Palette.textPrimary.color)
            Spacer()
            Button("Add…", action: addScripts)
            Button("Close", action: onClose)
        }
        .padding(Spacing.sm)
    }

    private var list: some View {
        List(ScriptLibrary.sorted(entries), selection: Binding(
            get: { selected },
            set: { newValue in selected = newValue; load(newValue) }
        )) { entry in
            HStack(spacing: Spacing.xs) {
                Image(systemName: entry.isBundled ? "shippingbox" : "doc.text")
                    .foregroundStyle(Palette.textSecondary.color)
                Text(entry.displayName)
                    .font(.system(size: TypeScale.body))
                    .foregroundStyle(Palette.textPrimary.color)
                if entry.isBundled { Spacer(); miniBadge("bundled") }
            }
            .tag(entry)
        }
        .listStyle(.sidebar)
        .overlay {
            if entries.isEmpty {
                Text("No scripts yet.\nAdd a .py file to get started.")
                    .multilineTextAlignment(.center)
                    .font(.system(size: TypeScale.body))
                    .foregroundStyle(Palette.textSecondary.color)
            }
        }
    }

    private var preview: some View {
        ScrollView {
            Text(source.isEmpty ? "Select a script to preview its source." : source)
                .font(.system(size: TypeScale.inspectorField, design: .monospaced))
                .foregroundStyle(source.isEmpty ? Palette.textSecondary.color : Palette.textPrimary.color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.sm)
        }
        .background(Palette.viewportBackground.color)
    }

    private func miniBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: TypeScale.caption, weight: .semibold))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).fill(Palette.accent.color.opacity(0.18)))
            .foregroundStyle(Palette.accent.color)
    }

    // MARK: Data

    private func reload() {
        entries = ScriptLibrary.sorted(bundledScripts() + entries.filter { !$0.isBundled })
    }

    /// Bundled starter scripts shipped in Resources/Python/scripts (dev-run
    /// walks up from cwd; the packaged app carries them in bundle resources).
    private func bundledScripts() -> [ScriptEntry] {
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("Resources/Python/scripts")
            if let urls = try? FileManager.default.contentsOfDirectory(
                at: candidate, includingPropertiesForKeys: nil) {
                return ScriptLibrary.scripts(from: urls, bundled: true)
            }
            dir.deleteLastPathComponent()
        }
        return []
    }

    private func addScripts() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "py")].compactMap { $0 }
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let added = ScriptLibrary.scripts(from: panel.urls, bundled: false)
        entries = ScriptLibrary.sorted(entries + added)
    }

    private func load(_ entry: ScriptEntry?) {
        guard let entry else { source = ""; return }
        source = (try? String(contentsOf: entry.url, encoding: .utf8)) ?? "// could not read \(entry.url.lastPathComponent)"
    }
}
