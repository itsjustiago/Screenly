import SwiftUI
import AppKit

final class UpdateModel: ObservableObject {
    @Published var status = ""
    @Published var failed = false
}

/// One-click updater: downloads the release .zip, swaps the app bundle and relaunches.
final class UpdateController: NSObject {
    private var window: NSWindow?
    private let model = UpdateModel()
    private var pageURL: URL?

    func start(_ info: UpdateInfo) {
        // Without a .zip asset we can't self-install — open the download page instead.
        guard let zipURL = info.zipURL else {
            NSWorkspace.shared.open(info.pageURL)
            return
        }
        pageURL = info.pageURL
        model.status = "A transferir o Screenly \(info.version)…"
        model.failed = false
        showWindow()
        URLSession.shared.downloadTask(with: zipURL) { [weak self] tmp, response, error in
            guard let self else { return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let tmp, error == nil, (200..<300).contains(code) else {
                self.fail("Não foi possível transferir a atualização.")
                return
            }
            self.install(downloaded: tmp)
        }.resume()
    }

    // MARK: - Install

    private func install(downloaded tmp: URL) {
        DispatchQueue.main.async { self.model.status = "A instalar…" }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("ScreenlyUpdate-\(UUID().uuidString)")
        let zip = work.appendingPathComponent("Screenly.zip")
        let extractDir = work.appendingPathComponent("extract")
        do {
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            try fm.moveItem(at: tmp, to: zip)
        } catch {
            fail("Falha ao preparar a atualização."); return
        }

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, extractDir.path]
        do { try ditto.run(); ditto.waitUntilExit() } catch { fail("Falha ao extrair."); return }
        guard ditto.terminationStatus == 0, let newApp = findApp(in: extractDir) else {
            fail("O pacote transferido é inválido."); return
        }

        swapAndRelaunch(newApp: newApp)
    }

    private func findApp(in dir: URL) -> URL? {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        if let app = items.first(where: { $0.pathExtension == "app" }) { return app }
        for item in items {
            if let sub = try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil),
               let app = sub.first(where: { $0.pathExtension == "app" }) {
                return app
            }
        }
        return nil
    }

    private func swapAndRelaunch(newApp: URL) {
        let dest = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        // Move the old bundle aside, copy the new one in; restore on failure so the
        // app is never left missing.
        let log = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Screenly/update.log").path
        let script = """
        #!/bin/bash
        unset SCREENLY_DEBUG_VERSION
        NEW="\(newApp.path)"
        DEST="\(dest)"
        LOG="\(log)"
        BACKUP="$DEST.old-$$"
        echo "$(date) --- swap start NEW=$NEW DEST=$DEST" >> "$LOG"
        for i in $(seq 1 100); do kill -0 \(pid) 2>/dev/null || break; sleep 0.1; done
        sleep 0.3
        /usr/bin/xattr -dr com.apple.quarantine "$NEW" 2>/dev/null
        /bin/mv "$DEST" "$BACKUP" 2>/dev/null
        if /usr/bin/ditto "$NEW" "$DEST"; then
          /bin/rm -rf "$BACKUP"
          echo "$(date) ditto OK" >> "$LOG"
        else
          /bin/rm -rf "$DEST"; /bin/mv "$BACKUP" "$DEST"
          echo "$(date) ditto FAILED, restored backup" >> "$LOG"
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
        LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        "$LSREG" -f "$DEST" 2>/dev/null
        sleep 0.5
        /usr/bin/open "$DEST"
        echo "$(date) open status=$? dest_exists=$([ -d "$DEST" ] && echo yes || echo no)" >> "$LOG"
        sleep 2
        if ! /usr/bin/pgrep -f "$DEST/Contents/MacOS/Screenly" >/dev/null 2>&1; then
          echo "$(date) not up after open — launching binary directly" >> "$LOG"
          "$DEST/Contents/MacOS/Screenly" >/dev/null 2>&1 &
        fi
        echo "$(date) done" >> "$LOG"
        """
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("screenly-update-\(UUID().uuidString).sh")
        do { try script.write(to: scriptURL, atomically: true, encoding: .utf8) }
        catch { fail("Falha ao preparar a instalação."); return }

        let bash = Process()
        bash.executableURL = URL(fileURLWithPath: "/bin/bash")
        bash.arguments = [scriptURL.path]
        do { try bash.run() } catch { fail("Falha ao instalar a atualização."); return }

        DispatchQueue.main.async { self.model.status = "A reiniciar…" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.terminate(nil) }
    }

    // MARK: - Window

    private func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 170),
                             styleMask: [.titled], backing: .buffered, defer: false)
            w.title = "Atualizar o Screenly"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: UpdateView(model: model, openPage: { [weak self] in
                if let url = self?.pageURL { NSWorkspace.shared.open(url) }
            }))
            window = w
        }
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.window?.center()
            self?.window?.makeKeyAndOrderFront(nil)
            self?.window?.orderFrontRegardless()
        }
    }

    private func fail(_ message: String) {
        DispatchQueue.main.async {
            self.model.status = message
            self.model.failed = true
        }
    }
}

struct UpdateView: View {
    @ObservedObject var model: UpdateModel
    var openPage: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            if model.failed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)
            } else {
                ProgressView().controlSize(.large)
            }
            Text(model.status)
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if model.failed {
                Button("Abrir página de transferência", action: openPage)
            }
        }
        .padding(24)
        .frame(width: 360, height: 170)
    }
}
