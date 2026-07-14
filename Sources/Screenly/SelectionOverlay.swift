import SwiftUI
import AppKit
import ScreenCaptureKit

// MARK: - Screen freeze

struct FrozenScreen {
    let image: NSImage
    let frame: CGRect
    let scale: CGFloat
}

/// Captures a still of the display under the cursor via ScreenCaptureKit, so the
/// selection + annotation happen over a frozen image (nothing shifts underneath).
enum ScreenFreezer {
    static func capture(completion: @escaping (FrozenScreen?) -> Void) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen,
              let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            completion(nil); return
        }
        // Extract Sendable value types up front — don't capture the NSScreen.
        let displayID = CGDirectDisplayID(num.uint32Value)
        let scale = screen.backingScaleFactor
        let frame = screen.frame

        Task {
            do {
                let content = try await SCShareableContent.current
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    await MainActor.run { completion(nil) }; return
                }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = Int(frame.width * scale)
                config.height = Int(frame.height * scale)
                config.showsCursor = false
                let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                let image = NSImage(cgImage: cg, size: frame.size)
                await MainActor.run { completion(FrozenScreen(image: image, frame: frame, scale: scale)) }
            } catch {
                NSLog("Screenly: screen freeze failed: \(error.localizedDescription)")
                await MainActor.run { completion(nil) }
            }
        }
    }
}

// MARK: - Shared selection state (view ↔ controller)

final class SelectionState: ObservableObject {
    @Published var rect: CGRect?
}

/// Borderless panel that can still become key so it receives Esc / ⌘-shortcuts.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Controller

/// Drives the region capture: freeze → selection + annotation overlay → export.
@MainActor
final class SelectionOverlayController: NSObject {
    private let store: CaptureStore
    private let preview = CapturePreview()
    private let fallback: (CaptureMode) -> Void

    private var panel: OverlayPanel?
    private var keyMonitor: Any?
    private var frozen: FrozenScreen?
    private let selection = SelectionState()
    private let model = AnnotationModel()

    /// `fallback` runs a plain non-editor capture if the freeze isn't available.
    init(store: CaptureStore, fallback: @escaping (CaptureMode) -> Void) {
        self.store = store
        self.fallback = fallback
    }

    func begin() {
        guard panel == nil else { return }
        ScreenFreezer.capture { [weak self] frozen in
            guard let self else { return }
            guard let frozen else { self.fallback(.region); return }
            self.present(frozen)
        }
    }

    /// Debug: present the overlay over a synthetic frozen image (no capture needed).
    func beginDebug() {
        guard panel == nil, let screen = NSScreen.main,
              let img = AppDelegate.debugImage(screen.frame.size) else { return }
        present(FrozenScreen(image: img, frame: screen.frame, scale: screen.backingScaleFactor))
    }

    private func present(_ frozen: FrozenScreen) {
        self.frozen = frozen
        model.shapes = []
        model.tool = .select
        selection.rect = nil

        let panel = OverlayPanel(contentRect: frozen.frame,
                                 styleMask: [.borderless], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.setFrame(frozen.frame, display: true)

        let view = SelectionOverlayView(
            frozen: frozen, model: model, selection: selection,
            onExport: { [weak self] rect, toClipboard in self?.export(rect, toClipboard: toClipboard) },
            onCancel: { [weak self] in self?.close() })
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: frozen.frame.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        self.panel = panel

        installKeyMonitor()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let cmd = event.modifierFlags.contains(.command)
            // While editing a text box, let all keys reach the field (except Esc).
            if self.model.editingTextID != nil {
                if event.keyCode == 53 { self.model.endTextEditing(); return nil }  // Esc ends editing
                return event
            }
            switch event.keyCode {
            case 53: self.close(); return nil                                        // Esc
            case 51, 117:                                                            // Delete / Fwd-delete
                self.model.deleteSelected(); return nil
            default: break
            }
            if cmd, let c = event.charactersIgnoringModifiers?.lowercased() {
                switch c {
                case "z": self.model.undo(); return nil
                case "c": if let r = self.selection.rect { self.export(r, toClipboard: true) }; return nil
                case "s": if let r = self.selection.rect { self.export(r, toClipboard: false) }; return nil
                default: break
                }
            }
            return event
        }
    }

    // MARK: Export

    private func export(_ rect: CGRect, toClipboard: Bool) {
        guard let frozen, rect.width > 2, rect.height > 2,
              let cg = render(frozen: frozen, shapes: model.shapes, selection: rect) else { close(); return }
        let ext = CaptureSettings.format
        guard let data = imageData(cg, ext: ext) else { close(); return }

        var savedURL: URL?
        if toClipboard {
            if let img = NSImage(data: data) { CaptureOutput.copyToClipboard(img) }
        } else {
            savedURL = CaptureOutput.saveToFolder(data, ext: ext)
        }
        let internalURL = store.add(data: data, ext: ext, mode: .region, savedPath: savedURL?.path)
        if CaptureSettings.showPreview, let url = savedURL ?? internalURL, let img = NSImage(contentsOf: url) {
            preview.show(image: img, reveal: savedURL ?? internalURL)
        }
        close()
    }

    /// Render the frozen image + annotations and crop to the selection, at full
    /// pixel resolution. WYSIWYG: same `ShapesCanvas` as the live overlay.
    private func render(frozen: FrozenScreen, shapes: [AnnotationShape], selection: CGRect) -> CGImage? {
        let w = frozen.frame.width, h = frozen.frame.height
        let content = ZStack(alignment: .topLeading) {
            Image(nsImage: frozen.image).resizable().frame(width: w, height: h)
            ShapesCanvas(shapes: shapes).frame(width: w, height: h)
        }
        .frame(width: w, height: h)

        let renderer = ImageRenderer(content: content)
        renderer.scale = frozen.scale
        guard let full = renderer.cgImage else { return nil }
        let s = frozen.scale
        let crop = CGRect(x: selection.minX * s, y: selection.minY * s,
                          width: selection.width * s, height: selection.height * s).integral
        return full.cropping(to: crop)
    }

    private func imageData(_ cg: CGImage, ext: String) -> Data? {
        let rep = NSBitmapImageRep(cgImage: cg)
        if ext == "jpg" { return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) }
        return rep.representation(using: .png, properties: [:])
    }

    func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel?.orderOut(nil)
        panel = nil
        frozen = nil
        model.shapes = []
        selection.rect = nil
    }
}

// MARK: - View

struct SelectionOverlayView: View {
    let frozen: FrozenScreen
    @ObservedObject var model: AnnotationModel
    @ObservedObject var selection: SelectionState
    var onExport: (CGRect, Bool) -> Void
    var onCancel: () -> Void

    @State private var dragMode: DragMode = .none
    @State private var anchorRect: CGRect = .zero
    @FocusState private var textFocused: Bool

    private enum Handle { case tl, tr, bl, br, t, b, l, r }
    private enum DragMode: Equatable { case none, newSel, move, resize(Handle), draw, text, ignore }

    var body: some View {
        GeometryReader { geo in
            let bounds = geo.size
            ZStack(alignment: .topLeading) {
                Image(nsImage: frozen.image)
                    .resizable()
                    .frame(width: bounds.width, height: bounds.height)

                dimLayer(bounds)

                ShapesCanvas(shapes: model.shapes, live: model.live,
                             selectedID: model.selectedID, editingTextID: model.editingTextID)
                    .frame(width: bounds.width, height: bounds.height)
                    .mask(alignment: .topLeading) { maskRect }

                chromeLayer

                editingText

                // Gesture surface (below the toolbar so its buttons keep working).
                Color.white.opacity(0.001)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { changed($0, bounds: bounds) }
                        .onEnded { ended($0, bounds: bounds) })

                if let rect = selection.rect, rect.width > 8, rect.height > 8 {
                    toolbar(rect: rect, bounds: bounds)
                }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Layers

    private func dimLayer(_ bounds: CGSize) -> some View {
        Canvas { ctx, size in
            var p = Path(CGRect(origin: .zero, size: size))
            if let r = selection.rect { p.addRect(r) }
            ctx.fill(p, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder private var maskRect: some View {
        if let r = selection.rect {
            Rectangle().frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
        } else {
            Color.clear
        }
    }

    private var chromeLayer: some View {
        Canvas { ctx, _ in
            guard let r = selection.rect else { return }
            ctx.stroke(Path(r), with: .color(Brand.tint), style: StrokeStyle(lineWidth: 1.5))
            if model.tool == .select {
                for p in handlePoints(r) {
                    let box = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
                    ctx.fill(Path(roundedRect: box, cornerRadius: 2), with: .color(.white))
                    ctx.stroke(Path(roundedRect: box, cornerRadius: 2), with: .color(Brand.tint), style: StrokeStyle(lineWidth: 1))
                }
            }
            // Dimension label
            let label = "\(Int(r.width)) × \(Int(r.height))"
            let resolved = ctx.resolve(Text(label).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundColor(.white))
            let ls = resolved.measure(in: CGSize(width: 200, height: 40))
            let lx = min(max(r.minX, 4), r.maxX)
            let ly = max(r.minY - ls.height - 6, 4)
            let bg = CGRect(x: lx, y: ly, width: ls.width + 12, height: ls.height + 6)
            ctx.fill(Path(roundedRect: bg, cornerRadius: 5), with: .color(.black.opacity(0.6)))
            ctx.draw(resolved, at: CGPoint(x: bg.midX, y: bg.midY), anchor: .center)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder private var editingText: some View {
        if let id = model.editingTextID, let shape = model.shapes.first(where: { $0.id == id }) {
            let fontSize = max(12, shape.lineWidth * 3)
            TextField("Texto", text: Binding(
                get: { shape.text },
                set: { model.setText($0, for: id) }))
                .textFieldStyle(.plain)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundColor(shape.color)
                .frame(width: 260, alignment: .leading)
                .position(x: shape.a.x + 130, y: shape.a.y + fontSize * 0.6)
                .focused($textFocused)
                .onSubmit { model.endTextEditing() }
                .onAppear { textFocused = true }
        }
    }

    private func toolbar(rect: CGRect, bounds: CGSize) -> some View {
        let half: CGFloat = 340
        let belowY = rect.maxY + 34
        let y = belowY + 20 < bounds.height ? belowY : max(rect.minY - 34, 34)
        let x = bounds.width < half * 2 ? bounds.width / 2 : min(max(rect.midX, half), bounds.width - half)
        return AnnotationToolbar(
            model: model,
            onCopy: { onExport(rect, true) },
            onSave: { onExport(rect, false) },
            onCancel: onCancel)
            .position(x: x, y: y)
    }

    // MARK: Gesture

    private func changed(_ v: DragGesture.Value, bounds: CGSize) {
        if dragMode == .none { startDrag(v) }
        switch dragMode {
        case .newSel:
            selection.rect = normalized(from: v.startLocation, to: clamp(v.location, in: bounds))
        case .move:
            selection.rect = clampRect(anchorRect.offsetBy(dx: v.translation.width, dy: v.translation.height), in: bounds)
        case .resize(let h):
            selection.rect = resize(anchorRect, handle: h, by: v.translation, in: bounds)
        case .draw:
            model.updateDraw(to: v.location)
        default:
            break
        }
    }

    private func ended(_ v: DragGesture.Value, bounds: CGSize) {
        switch dragMode {
        case .draw:
            model.endDraw()
        case .text:
            if let r = selection.rect, r.contains(v.location) { model.addText(at: v.location) }
        case .move:
            // A tap (no real drag) inside the selection = pick a shape to edit.
            if abs(v.translation.width) < 3, abs(v.translation.height) < 3 {
                model.selectShape(at: v.startLocation)
            } else if let r = selection.rect {
                selection.rect = r.standardized
            }
        case .resize:
            if let r = selection.rect { selection.rect = r.standardized }
        case .newSel:
            model.selectedID = nil
        default:
            break
        }
        dragMode = .none
    }

    private func startDrag(_ v: DragGesture.Value) {
        let p = v.startLocation
        if model.editingTextID != nil { model.endTextEditing() }

        guard let r = selection.rect else {
            dragMode = .newSel
            selection.rect = CGRect(origin: p, size: .zero)
            return
        }

        switch model.tool {
        case .select:
            if let h = handleHit(r, at: p) { dragMode = .resize(h); anchorRect = r }
            else if r.insetBy(dx: -4, dy: -4).contains(p) { dragMode = .move; anchorRect = r }
            else { dragMode = .newSel; selection.rect = CGRect(origin: p, size: .zero) }
        case .text:
            dragMode = .text
        default:
            if r.insetBy(dx: -2, dy: -2).contains(p) { dragMode = .draw; model.beginDraw(at: p) }
            else { dragMode = .ignore }
        }
    }

    // MARK: Geometry helpers

    private func handlePoints(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
         CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY),
         CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.midX, y: r.maxY),
         CGPoint(x: r.minX, y: r.midY), CGPoint(x: r.maxX, y: r.midY)]
    }

    private func handleHit(_ r: CGRect, at p: CGPoint) -> Handle? {
        let hit: CGFloat = 12
        func near(_ pt: CGPoint) -> Bool { abs(p.x - pt.x) <= hit && abs(p.y - pt.y) <= hit }
        if near(CGPoint(x: r.minX, y: r.minY)) { return .tl }
        if near(CGPoint(x: r.maxX, y: r.minY)) { return .tr }
        if near(CGPoint(x: r.minX, y: r.maxY)) { return .bl }
        if near(CGPoint(x: r.maxX, y: r.maxY)) { return .br }
        if near(CGPoint(x: r.midX, y: r.minY)) { return .t }
        if near(CGPoint(x: r.midX, y: r.maxY)) { return .b }
        if near(CGPoint(x: r.minX, y: r.midY)) { return .l }
        if near(CGPoint(x: r.maxX, y: r.midY)) { return .r }
        return nil
    }

    private func resize(_ r: CGRect, handle: Handle, by t: CGSize, in bounds: CGSize) -> CGRect {
        var minX = r.minX, minY = r.minY, maxX = r.maxX, maxY = r.maxY
        switch handle {
        case .tl: minX += t.width; minY += t.height
        case .tr: maxX += t.width; minY += t.height
        case .bl: minX += t.width; maxY += t.height
        case .br: maxX += t.width; maxY += t.height
        case .t:  minY += t.height
        case .b:  maxY += t.height
        case .l:  minX += t.width
        case .r:  maxX += t.width
        }
        let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).standardized
        return clampRect(rect, in: bounds)
    }

    private func normalized(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func clamp(_ p: CGPoint, in bounds: CGSize) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
    }

    private func clampRect(_ r: CGRect, in bounds: CGSize) -> CGRect {
        var rect = r
        if rect.minX < 0 { rect.origin.x = 0 }
        if rect.minY < 0 { rect.origin.y = 0 }
        if rect.maxX > bounds.width { rect.origin.x = min(rect.origin.x, bounds.width - rect.width) }
        if rect.maxY > bounds.height { rect.origin.y = min(rect.origin.y, bounds.height - rect.height) }
        return rect
    }
}
