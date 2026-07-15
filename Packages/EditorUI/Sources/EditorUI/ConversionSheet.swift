import SwiftUI
import UniformTypeIdentifiers
import ConversionKit
import DicyaninDesignSystem

/// Single-file conversion sheet (Phase 2). Wraps `SingleFileConverter` with a
/// preset picker, texture options, a live log, and diagnostics. Writes the
/// resulting `.usda` next to the source or to a chosen location.
struct ConversionSheet: View {
    let onClose: () -> Void

    @State private var inputURL: URL?
    @State private var preset: ConversionPreset = .quickLookStrict
    @State private var maxTextureSize: Double = 2048
    @State private var encodeJPEG = false

    @State private var isRunning = false
    @State private var log: [String] = []
    @State private var outcome: ConversionOutcome?
    @State private var errorText: String?
    @State private var savedURL: URL?

    private let registry = ImporterRegistry.standard

    private var texturePolicy: TexturePolicy {
        TexturePolicy(maxSize: Int(maxTextureSize),
                      encodeBaseColorAsJPEG: encodeJPEG,
                      jpegQuality: preset.texturePolicy.jpegQuality)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Convert to USD")
                .font(.system(size: TypeScale.title, weight: .semibold))
                .foregroundStyle(Palette.textPrimary.color)

            filePicker
            options
            Divider().overlay(Palette.panelBorder.color)
            logView

            HStack {
                if let errorText {
                    Label(errorText, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(Palette.error.color)
                        .font(.system(size: TypeScale.body))
                } else if let savedURL {
                    Label("Saved \(savedURL.lastPathComponent)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Palette.accent.color)
                        .font(.system(size: TypeScale.body))
                }
                Spacer()
                Button("Close", action: onClose)
                Button(action: run) {
                    if isRunning { ProgressView().controlSize(.small) }
                    else { Text("Convert") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(inputURL == nil || isRunning)
            }
        }
        .padding(Spacing.lg)
        .frame(width: 560, height: 520)
        .background(Palette.windowBackground.color)
    }

    private var filePicker: some View {
        HStack(spacing: Spacing.sm) {
            Button("Choose File…", action: pickInput)
            Text(inputURL?.lastPathComponent ?? "No file selected")
                .font(.system(size: TypeScale.body, design: .monospaced))
                .foregroundStyle(Palette.textSecondary.color)
                .lineLimit(1)
            Spacer()
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Picker("Preset", selection: $preset) {
                ForEach(ConversionPreset.builtins) { p in Text(p.name).tag(p) }
            }
            .onChange(of: preset) { _, p in
                maxTextureSize = Double(p.texturePolicy.maxSize)
                encodeJPEG = p.texturePolicy.encodeBaseColorAsJPEG
            }
            Text(preset.summary)
                .font(.system(size: TypeScale.caption))
                .foregroundStyle(Palette.textSecondary.color)

            HStack {
                Text("Max texture size")
                    .font(.system(size: TypeScale.body))
                    .foregroundStyle(Palette.textSecondary.color)
                Picker("", selection: $maxTextureSize) {
                    ForEach([512.0, 1024, 2048, 4096], id: \.self) { Text("\(Int($0))").tag($0) }
                }
                .labelsHidden()
                .frame(width: 100)
                Toggle("Encode base color as JPEG", isOn: $encodeJPEG)
                    .font(.system(size: TypeScale.body))
            }
            Text("Supported inputs: \(registry.registeredExtensions.joined(separator: ", "))")
                .font(.system(size: TypeScale.caption))
                .foregroundStyle(Palette.textSecondary.color)
        }
    }

    private var logView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                if log.isEmpty {
                    Text("Conversion log will appear here.")
                        .font(.system(size: TypeScale.body))
                        .foregroundStyle(Palette.textSecondary.color)
                }
                ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: TypeScale.inspectorField, design: .monospaced))
                        .foregroundStyle(Palette.textPrimary.color)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let outcome, !outcome.diagnostics.isEmpty {
                    ForEach(Array(outcome.diagnostics.enumerated()), id: \.offset) { _, d in
                        Text("• \(d.severity.rawValue): \(d.message)")
                            .font(.system(size: TypeScale.inspectorField, design: .monospaced))
                            .foregroundStyle(diagColor(d.severity).color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(Spacing.xs)
        }
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.viewportBackground.color))
    }

    private func diagColor(_ s: DiagnosticSeverity) -> ColorToken {
        switch s {
        case .error: return Palette.error
        case .warning: return Palette.warning
        case .info: return Palette.textSecondary
        }
    }

    private func pickInput() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = registry.registeredExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            inputURL = panel.url
            log = []; outcome = nil; errorText = nil; savedURL = nil
        }
    }

    private func run() {
        guard let inputURL else { return }
        isRunning = true; errorText = nil; savedURL = nil; log = ["converting \(inputURL.lastPathComponent)…"]
        let policy = texturePolicy
        Task {
            do {
                let result = try await SingleFileConverter.convert(
                    input: inputURL, registry: registry, texturePolicy: policy)
                await MainActor.run {
                    outcome = result
                    log = result.log
                    save(result, source: inputURL)
                    isRunning = false
                }
            } catch {
                await MainActor.run {
                    errorText = "\(error)"
                    isRunning = false
                }
            }
        }
    }

    private func save(_ outcome: ConversionOutcome, source: URL) {
        let out = source.deletingPathExtension().appendingPathExtension("usda")
        let panel = NSSavePanel()
        panel.nameFieldStringValue = out.lastPathComponent
        panel.allowedContentTypes = [UTType(filenameExtension: "usda")].compactMap { $0 }
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        do {
            try outcome.usda.write(to: dest, atomically: true, encoding: .utf8)
            savedURL = dest
        } catch {
            errorText = "write failed: \(error)"
        }
    }
}
