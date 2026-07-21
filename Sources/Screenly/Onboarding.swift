import SwiftUI
import AppKit
import CoreGraphics

/// Tracks whether Screen Recording is granted, refreshing live while open.
final class OnboardingModel: ObservableObject {
    @Published var trusted = CGPreflightScreenCaptureAccess()
    private var timer: Timer?

    func startWatching() {
        trusted = CGPreflightScreenCaptureAccess()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.trusted = CGPreflightScreenCaptureAccess()
        }
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }
}

/// First-run welcome window: explains the capture shortcuts and offers the
/// Screen Recording grant. Ported from Clippy's onboarding.
final class OnboardingController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model = OnboardingModel()

    func show() {
        if window == nil { build() }
        model.startWatching()
        // Defer to the next runloop and force front — an accessory (LSUIElement)
        // app won't present a window reliably during launch otherwise.
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.center()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private func build() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 500),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.title = "Screenly"
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = NSHostingView(
            rootView: OnboardingView(model: model, onClose: { [weak self] in self?.window?.close() }))
        window = w
    }

    func windowWillClose(_ notification: Notification) {
        model.stopWatching()
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                AppIcon(systemName: "camera.viewfinder", size: 64)
                Text("Bem-vindo ao Screenly")
                    .font(.system(size: 22, weight: .bold))
                Text("Screenshots rápidos, direto da barra de menus.")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 14) {
                infoRow(icon: CaptureMode.region.systemImage,
                        title: "Região  ·  \(Shortcut.display(CaptureMode.region))",
                        text: "Arrasta para selecionar uma área. Espaço alterna para modo janela.")
                infoRow(icon: CaptureMode.screen.systemImage,
                        title: "Ecrã inteiro  ·  \(Shortcut.display(CaptureMode.screen))",
                        text: "Captura tudo de uma vez. Muda os atalhos nas Definições.")
                permissionCard
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 16)

            Button(action: onClose) {
                Text("Começar").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(Brand.tint)
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 28)
            .padding(.bottom, 26)
        }
        .frame(width: 460, height: 500)
    }

    private var permissionCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: model.trusted ? "checkmark.circle.fill" : "hand.raised.fill")
                .font(.system(size: 20))
                .foregroundStyle(model.trusted ? .green : .orange)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.trusted ? "Gravação de ecrã ativa" : "Ativar gravação de ecrã")
                    .font(.system(size: 14, weight: .semibold))
                Text(model.trusted
                     ? "Está tudo pronto — já podes capturar."
                     : "O Screenly precisa desta permissão para capturar o ecrã.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !model.trusted {
                    Button("Conceder acesso…") { grantAccess() }
                        .controlSize(.small)
                        .padding(.top, 3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            (model.trusted ? Color.green : Color.orange).opacity(0.10),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder((model.trusted ? Color.green : Color.orange).opacity(0.22))
        )
        .animation(.easeInOut(duration: 0.2), value: model.trusted)
    }

    private func grantAccess() {
        // Triggers the system prompt, then opens the exact Settings pane.
        _ = CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func infoRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AppIcon(systemName: icon, size: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
