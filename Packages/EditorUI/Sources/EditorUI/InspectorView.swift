import SwiftUI
import USDCore
import DicyaninDesignSystem

/// The read-only inspector (Phase 1). Replaces the Phase 0 placeholder with a
/// tabbed view over the selected prim and the stage. Editing lands in Phase 3;
/// the seams (attributes, relationships, metadata) are already surfaced.
struct InspectorView: View {
    let stage: (any USDStageProtocol)?
    let selection: Selection

    enum Tab: String, CaseIterable, Identifiable {
        case prim = "Prim"
        case transform = "Transform"
        case material = "Material"
        case stage = "Stage"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .prim

    private var prim: Prim? {
        guard let stage, let path = selection.primary else { return nil }
        return stage.prim(at: path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(Spacing.xs)

            Divider().overlay(Palette.panelBorder.color)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    switch tab {
                    case .prim: primTab
                    case .transform: transformTab
                    case .material: materialTab
                    case .stage: stageTab
                    }
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Palette.panelBackground.color)
    }

    // MARK: Prim

    @ViewBuilder
    private var primTab: some View {
        if let prim {
            PanelSection(title: "Prim") {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    FieldRow(label: "Path", value: prim.path.description)
                    FieldRow(label: "Type", value: prim.typeName.isEmpty ? "(typeless)" : prim.typeName)
                    FieldRow(label: "Active", value: prim.isActive ? "true" : "false")
                    FieldRow(label: "Visibility", value: prim.visibility.rawValue)
                    FieldRow(label: "Children", value: String(prim.children.count))
                }
            }
            if !prim.metadata.isEmpty {
                PanelSection(title: "Metadata") {
                    ForEach(prim.metadata.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                        FieldRow(label: k, value: v)
                    }
                }
            }
            attributesSection(prim.attributes)
            if !prim.relationships.isEmpty {
                PanelSection(title: "Relationships") {
                    ForEach(prim.relationships, id: \.name) { rel in
                        FieldRow(label: rel.name,
                                 value: rel.targets.map(\.description).joined(separator: ", "))
                    }
                }
            }
            if !prim.variantSets.isEmpty {
                PanelSection(title: "Variant Sets") {
                    ForEach(prim.variantSets, id: \.name) { vs in
                        FieldRow(label: vs.name,
                                 value: (vs.selection ?? "—") + "  {\(vs.variants.joined(separator: ", "))}")
                    }
                }
            }
        } else {
            emptyState("No selection")
        }
    }

    @ViewBuilder
    private func attributesSection(_ attributes: [Attribute]) -> some View {
        if !attributes.isEmpty {
            PanelSection(title: "Attributes (\(attributes.count))") {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(attributes.sorted(by: { $0.name < $1.name }), id: \.name) { attr in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: Spacing.xs) {
                                Text(attr.name)
                                    .font(.system(size: TypeScale.body, weight: .medium))
                                    .foregroundStyle(Palette.textPrimary.color)
                                Text(attr.value.typeLabel)
                                    .font(.system(size: TypeScale.caption, design: .monospaced))
                                    .foregroundStyle(Palette.textSecondary.color)
                                if attr.isUniform { badge("uniform") }
                                if attr.isAnimated { badge("anim") }
                            }
                            Text(ValueFormatter.string(attr.value))
                                .font(.system(size: TypeScale.inspectorField, design: .monospaced))
                                .foregroundStyle(Palette.textSecondary.color)
                                .textSelection(.enabled)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    // MARK: Transform

    @ViewBuilder
    private var transformTab: some View {
        if let prim {
            let xformAttrs = prim.attributes.filter { $0.name.hasPrefix("xformOp") }
            if xformAttrs.isEmpty {
                emptyState("No transform ops authored on this prim.")
            } else {
                PanelSection(title: "Transform Ops") {
                    ForEach(xformAttrs, id: \.name) { attr in
                        FieldRow(label: attr.name.replacingOccurrences(of: "xformOp:", with: ""),
                                 value: ValueFormatter.string(attr.value))
                    }
                }
            }
        } else {
            emptyState("No selection")
        }
    }

    // MARK: Material

    @ViewBuilder
    private var materialTab: some View {
        if let prim {
            let binding = prim.relationships.first { $0.name.contains("material:binding") }
            let shaderAttrs = prim.attributes.filter { $0.name.hasPrefix("inputs:") }
            if binding == nil && shaderAttrs.isEmpty {
                emptyState("No material binding or shader inputs on this prim.")
            } else {
                if let binding {
                    PanelSection(title: "Binding") {
                        FieldRow(label: "material", value: binding.targets.map(\.description).joined(separator: ", "))
                    }
                }
                if !shaderAttrs.isEmpty {
                    PanelSection(title: "Shader Inputs") {
                        ForEach(shaderAttrs, id: \.name) { attr in
                            FieldRow(label: attr.name.replacingOccurrences(of: "inputs:", with: ""),
                                     value: ValueFormatter.string(attr.value))
                        }
                    }
                }
            }
        } else {
            emptyState("No selection")
        }
    }

    // MARK: Stage

    @ViewBuilder
    private var stageTab: some View {
        if let stage {
            let m = stage.metadata
            PanelSection(title: "Stage") {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    FieldRow(label: "Source", value: stage.sourceURL?.lastPathComponent ?? "—")
                    FieldRow(label: "Up axis", value: m.upAxis.rawValue)
                    FieldRow(label: "Meters/unit", value: String(format: "%g", m.metersPerUnit))
                    FieldRow(label: "Default prim", value: m.defaultPrim ?? "—")
                    FieldRow(label: "Prims", value: String(stage.primCount))
                }
            }
            if m.isAnimated {
                PanelSection(title: "Animation") {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        FieldRow(label: "Start", value: m.startTimeCode.map { String(format: "%g", $0) } ?? "—")
                        FieldRow(label: "End", value: m.endTimeCode.map { String(format: "%g", $0) } ?? "—")
                        FieldRow(label: "FPS", value: m.timeCodesPerSecond.map { String(format: "%g", $0) } ?? "—")
                    }
                }
            }
            if !m.customLayerData.isEmpty {
                PanelSection(title: "Custom Layer Data") {
                    ForEach(m.customLayerData.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                        FieldRow(label: k, value: v)
                    }
                }
            }
        } else {
            emptyState("No stage open")
        }
    }

    // MARK: Helpers

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: TypeScale.caption, weight: .semibold))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).fill(Palette.accent.color.opacity(0.2)))
            .foregroundStyle(Palette.accent.color)
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.system(size: TypeScale.body))
            .foregroundStyle(Palette.textSecondary.color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
