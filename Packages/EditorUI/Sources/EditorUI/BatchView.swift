import SwiftUI
import UniformTypeIdentifiers
import ConversionKit
import DicyaninDesignSystem

/// Batch converter window (Phase 2). Drops multiple source files, runs them
/// through `BatchConverter`, streams per-item results, and exports the
/// CSV/JSON report the engine already produces.
struct BatchView: View {
    let onClose: () -> Void

    @State private var jobs: [BatchJob] = []
    @State private var results: [BatchItemResult] = []
    @State private var outputDir: URL?
    @State private var overwrite = true
    @State private var isRunning = false
    @State private var report: BatchReport?
    @State private var status: String?

    private let registry = ImporterRegistry.standard

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Batch Convert")
                    .font(.system(size: TypeScale.title, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary.color)
                Spacer()
                Button("Add Files…", action: addFiles)
                Button("Output Folder…", action: pickOutput)
                Toggle("Overwrite", isOn: $overwrite)
                    .font(.system(size: TypeScale.body))
            }

            HStack(spacing: Spacing.sm) {
                Text(outputDir.map { "→ \($0.path)" } ?? "Output: alongside each source")
                    .font(.system(size: TypeScale.caption, design: .monospaced))
                    .foregroundStyle(Palette.textSecondary.color)
                    .lineLimit(1)
                Spacer()
            }

            table

            if let report {
                HStack(spacing: Spacing.md) {
                    Text("\(report.succeededCount) ok")
                        .foregroundStyle(Palette.accent.color)
                    Text("\(report.failedCount) failed")
                        .foregroundStyle(report.hasFailures ? Palette.error.color : Palette.textSecondary.color)
                    Text("\(report.skippedCount) skipped")
                        .foregroundStyle(Palette.textSecondary.color)
                }
                .font(.system(size: TypeScale.body, weight: .medium))
            }

            HStack {
                if let status {
                    Text(status)
                        .font(.system(size: TypeScale.body))
                        .foregroundStyle(Palette.textSecondary.color)
                }
                Spacer()
                Button("Save CSV…", action: { saveReport(asJSON: false) })
                    .disabled(report == nil)
                Button("Save JSON…", action: { saveReport(asJSON: true) })
                    .disabled(report == nil)
                Button("Close", action: onClose)
                Button(action: run) {
                    if isRunning { ProgressView().controlSize(.small) }
                    else { Text("Run \(jobs.count) Job\(jobs.count == 1 ? "" : "s")") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(jobs.isEmpty || isRunning)
            }
        }
        .padding(Spacing.lg)
        .frame(width: 680, height: 540)
        .background(Palette.windowBackground.color)
    }

    private var table: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerRow
                if jobs.isEmpty {
                    Text("Add glTF/OBJ/STL/… files to queue conversions.")
                        .font(.system(size: TypeScale.body))
                        .foregroundStyle(Palette.textSecondary.color)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(Spacing.lg)
                }
                ForEach(Array(jobs.enumerated()), id: \.offset) { idx, job in
                    row(job: job, result: results.first { $0.input == job.input.path })
                    Divider().overlay(Palette.panelBorder.color.opacity(0.4))
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.panelBackground.color))
    }

    private var headerRow: some View {
        HStack(spacing: Spacing.sm) {
            cell("Input", width: 220, bold: true)
            cell("Status", width: 90, bold: true)
            cell("Tris", width: 70, bold: true)
            cell("Mats", width: 50, bold: true)
            cell("Warn", width: 50, bold: true)
            cell("Time", width: 70, bold: true)
        }
        .padding(.vertical, Spacing.xxs)
        .padding(.horizontal, Spacing.xs)
    }

    private func row(job: BatchJob, result: BatchItemResult?) -> some View {
        HStack(spacing: Spacing.sm) {
            cell(job.input.lastPathComponent, width: 220)
            statusCell(result?.status)
            cell(result.map { String($0.triangleCount) } ?? "—", width: 70)
            cell(result.map { String($0.materialCount) } ?? "—", width: 50)
            cell(result.map { String($0.warningCount) } ?? "—", width: 50)
            cell(result.map { String(format: "%.2fs", $0.durationSeconds) } ?? "—", width: 70)
        }
        .padding(.vertical, Spacing.xxs)
        .padding(.horizontal, Spacing.xs)
    }

    @ViewBuilder
    private func statusCell(_ status: BatchItemStatus?) -> some View {
        let (text, tint): (String, ColorToken) = {
            switch status {
            case .succeeded: return ("ok", Palette.accent)
            case .failed: return ("failed", Palette.error)
            case .skipped: return ("skipped", Palette.warning)
            case nil: return ("queued", Palette.textSecondary)
            }
        }()
        Text(text)
            .font(.system(size: TypeScale.body, weight: .medium))
            .foregroundStyle(tint.color)
            .frame(width: 90, alignment: .leading)
    }

    private func cell(_ text: String, width: CGFloat, bold: Bool = false) -> some View {
        Text(text)
            .font(.system(size: bold ? TypeScale.label : TypeScale.body,
                          weight: bold ? .semibold : .regular,
                          design: bold ? .default : .monospaced))
            .foregroundStyle(bold ? Palette.textSecondary.color : Palette.textPrimary.color)
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
    }

    // MARK: Actions

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = registry.registeredExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let newJobs = panel.urls.map { url -> BatchJob in
            let out = outputURL(for: url)
            return BatchJob(input: url, output: out)
        }
        jobs.append(contentsOf: newJobs)
        results = []; report = nil; status = nil
    }

    private func pickOutput() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let dir = panel.url {
            outputDir = dir
            // Re-target queued jobs at the new folder.
            jobs = jobs.map { BatchJob(input: $0.input, output: outputURL(for: $0.input)) }
        }
    }

    private func outputURL(for input: URL) -> URL {
        let name = input.deletingPathExtension().lastPathComponent + ".usda"
        let base = outputDir ?? input.deletingLastPathComponent()
        return base.appendingPathComponent(name)
    }

    private func run() {
        isRunning = true; results = []; report = nil
        status = "running \(jobs.count) job(s)…"
        let converter = BatchConverter(registry: registry, overwrite: overwrite)
        let queued = jobs
        Task {
            // Progress streaming crosses the actor boundary; collect off-actor
            // and publish once, which keeps the run @Sendable-clean.
            let finished = await converter.run(queued)
            await MainActor.run {
                report = finished
                results = finished.items
                isRunning = false
                status = "done"
            }
        }
    }

    private func saveReport(asJSON: Bool) {
        guard let report else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = asJSON ? "batch-report.json" : "batch-report.csv"
        panel.allowedContentTypes = [UTType(filenameExtension: asJSON ? "json" : "csv")].compactMap { $0 }
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        do {
            if asJSON {
                try report.jsonData().write(to: dest)
            } else {
                try Data(report.csv.utf8).write(to: dest)
            }
            status = "saved \(dest.lastPathComponent)"
        } catch {
            status = "save failed: \(error)"
        }
    }
}
