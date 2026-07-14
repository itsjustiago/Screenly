import SwiftUI

/// The floating annotation toolbar: tools, colours, fill, stroke width, undo and
/// the export actions. Shared by the region overlay and the editor window.
struct AnnotationToolbar: View {
    @ObservedObject var model: AnnotationModel
    var onCopy: () -> Void
    var onSave: () -> Void
    var onCancel: () -> Void

    private let widths: [(CGFloat, CGFloat)] = [(3, 6), (6, 9), (11, 13)]  // (lineWidth, dotSize)

    var body: some View {
        HStack(spacing: 12) {
            tools
            divider
            colors
            divider
            styleGroup
            divider
            actions
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.30), radius: 18, y: 7)
        .fixedSize()
    }

    // MARK: Tools

    private var tools: some View {
        HStack(spacing: 3) {
            ForEach(AnnotationTool.allCases) { tool in
                iconToggle(tool.systemImage, active: model.tool == tool, help: tool.label) {
                    model.tool = tool
                }
            }
        }
    }

    // MARK: Colours

    private var colors: some View {
        HStack(spacing: 7) {
            ForEach(AnnotationPalette.colors, id: \.self) { hex in
                Button { pick(hex) } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(.white.opacity(hex == "#FFFFFF" ? 0.5 : 0.22)))
                        .overlay(
                            Circle().strokeBorder(Color.primary, lineWidth: 2).padding(-3)
                                .opacity(isSelected(hex) ? 1 : 0)
                        )
                        .padding(3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Fill + width

    private var styleGroup: some View {
        HStack(spacing: 8) {
            iconToggle(model.filled ? "square.fill" : "square", active: model.filled,
                       help: "Preencher formas (tapar conteúdo)") {
                model.filled.toggle()
            }
            HStack(spacing: 3) {
                ForEach(widths, id: \.0) { w, dot in
                    Button { model.lineWidth = w } label: {
                        Circle()
                            .fill(model.lineWidth == w ? Color.primary : Color.secondary)
                            .frame(width: dot, height: dot)
                            .frame(width: 24, height: 26)
                            .background(model.lineWidth == w ? AnyShapeStyle(.primary.opacity(0.10)) : AnyShapeStyle(.clear),
                                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Espessura")
                }
            }
        }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 8) {
            iconButton("arrow.uturn.backward", help: "Anular (⌘Z)", enabled: model.canUndo) { model.undo() }
            iconButton("xmark", help: "Cancelar (Esc)", enabled: true, action: onCancel)
            Button(action: onCopy) {
                Label("Copiar", systemImage: "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 11).frame(height: 28)
                    .background(.primary.opacity(0.08), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Copiar para o clipboard (⌘C)")

            Button(action: onSave) {
                Label("Guardar", systemImage: "square.and.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13).frame(height: 28)
                    .background(Brand.tint, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Guardar em ficheiro (⌘S)")
        }
    }

    // MARK: Building blocks

    private func iconToggle(_ symbol: String, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 28)
                .foregroundStyle(active ? Color.white : .primary)
                .background(active ? AnyShapeStyle(Brand.tint) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func iconButton(_ symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 28)
                .opacity(enabled ? 1 : 0.35)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }

    private func pick(_ hex: String) {
        model.colorHex = hex
        if model.selectedID != nil { model.recolorSelected(hex) }
    }

    private func isSelected(_ hex: String) -> Bool {
        model.colorHex.caseInsensitiveCompare(hex) == .orderedSame
    }

    private var divider: some View {
        Rectangle().fill(.primary.opacity(0.12)).frame(width: 1, height: 22)
    }
}
