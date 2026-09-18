// Pyramid Principle — a standalone macOS app around the single-file web app.
//
// Everything it needs is inside the bundle and it opens no sockets. Resources
// reach the WKWebView through a custom `gt://` scheme rather than file:// or a
// loopback server:
//
//   • file:// works, but WKWebView refuses localStorage on file:// origins, so
//     every saved document would vanish on quit.
//   • a loopback server works, but needs a port that stays the same across
//     launches (or the origin changes and storage is lost), can collide with
//     whatever else holds that port, and can prompt the firewall.
//
//   gt://app has a fixed origin for the life of the app, needs no network, and
//   localStorage behaves exactly as it does on the web.

import Cocoa
import WebKit

let kScheme = "gt"
let kHome   = "gt://app/index.html"

// MARK: - Icon ───────────────────────────────────────────────────────────────
// The app's own mark: the pyramid with its key line.

func drawIcon(_ size: CGFloat) {
    let teal  = NSColor(srgbRed: 0.059, green: 0.322, blue: 0.341, alpha: 1)  // #0F5257
    let paper = NSColor(srgbRed: 0.929, green: 0.945, blue: 0.937, alpha: 1)  // #EDF1EF
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
                 xRadius: size * 0.2237, yRadius: size * 0.2237).addClip()
    teal.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let m = size * 0.23
    let tri = NSBezierPath()
    tri.move(to: NSPoint(x: size / 2, y: size - m))
    tri.line(to: NSPoint(x: size - m, y: m))
    tri.line(to: NSPoint(x: m, y: m))
    tri.close()
    tri.lineWidth = size * 0.055
    tri.lineJoinStyle = .round
    paper.setStroke()
    tri.stroke()

    let key = NSBezierPath()                       // the key line, at its true width
    key.move(to: NSPoint(x: size * 0.325, y: size * 0.425))
    key.line(to: NSPoint(x: size * 0.675, y: size * 0.425))
    key.lineWidth = size * 0.055
    key.stroke()
}

func iconImage(_ size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus(); drawIcon(size); img.unlockFocus()
    return img
}

func emitIconset(_ dir: String) {
    let sizes: [(Int, String)] = [
        (16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
        (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"),
        (512, "icon_256x256@2x"), (512, "icon_512x512"), (1024, "icon_512x512@2x"),
    ]
    for (px, name) in sizes {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
        rep.size = NSSize(width: px, height: px)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        drawIcon(CGFloat(px))
        NSGraphicsContext.restoreGraphicsState()
        if let d = rep.representation(using: .png, properties: [:]) {
            try? d.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        }
    }
}

// MARK: - Bundled resources ──────────────────────────────────────────────────

let mimes: [String: String] = [
    "html": "text/html; charset=utf-8", "css": "text/css; charset=utf-8",
    "js": "text/javascript; charset=utf-8", "json": "application/json",
    "woff2": "font/woff2", "woff": "font/woff", "ttf": "font/ttf", "otf": "font/otf",
    "svg": "image/svg+xml", "png": "image/png", "jpg": "image/jpeg", "webp": "image/webp",
]

/// Everything under Contents/Resources/www, keyed by the path the page asks for.
func loadResources() -> [String: (Data, String)] {
    var out: [String: (Data, String)] = [:]
    guard let root = Bundle.main.resourceURL?.appendingPathComponent("www"),
          let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
    else { return out }
    for case let url as URL in walker {
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
              let data = try? Data(contentsOf: url) else { continue }
        let rel = url.path.replacingOccurrences(of: root.path, with: "")
        out[rel] = (data, mimes[url.pathExtension.lowercased()] ?? "application/octet-stream")
    }
    return out
}

final class ResourceHandler: NSObject, WKURLSchemeHandler {
    private let files: [String: (Data, String)]
    init(_ files: [String: (Data, String)]) { self.files = files }

    func webView(_ w: WKWebView, start task: WKURLSchemeTask) {
        let raw = task.request.url?.path ?? "/"
        let path = (raw.isEmpty || raw == "/") ? "/index.html" : raw
        guard let (data, mime) = files[path], let url = task.request.url else {
            task.didFailWithError(NSError(domain: "gt", code: 404,
                userInfo: [NSLocalizedDescriptionKey: "no bundled resource at \(raw)"]))
            return
        }
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": mime,
                                                  "Content-Length": "\(data.count)",
                                                  "Cache-Control": "no-store"])!
        task.didReceive(resp)
        task.didReceive(data)
        task.didFinish()
    }
    func webView(_ w: WKWebView, stop task: WKURLSchemeTask) {}
}

// MARK: - Capability bridge ──────────────────────────────────────────────────
// The page asks for what it needs through `claude.use(name)`. In the artifact
// the viewer answers; here the app does — `downloads` with a real save panel,
// everything else with null, which is what the page's absence-handling expects.

let bridgeJS = """
(function () {
  if (window.claude) return;
  var seq = 0, pending = {};
  window.__gtResolve = function (id, ok, code) {
    var p = pending[id]; if (!p) return; delete pending[id];
    if (ok) p.res({ status: 'saved' });
    else p.rej({ code: code || 'declined', message: code || 'declined' });
  };
  var downloads = Object.freeze({
    save: function (req) {
      return new Promise(function (res, rej) {
        if (typeof req.data !== 'string') { rej({ code: 'bad_request', message: 'text only' }); return; }
        var id = ++seq; pending[id] = { res: res, rej: rej };
        window.webkit.messageHandlers.gt.postMessage({
          op: 'save', id: id, filename: String(req.filename || 'download.txt'), data: req.data
        });
      });
    }
  });
  window.claude = Object.freeze({
    use: function (name) { return Promise.resolve(name === 'downloads' ? downloads : null); }
  });
})();
"""

// MARK: - App ────────────────────────────────────────────────────────────────

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    var window: NSWindow!
    var web: WKWebView!
    var handler: ResourceHandler!
    let selftest = CommandLine.arguments.contains("--selftest")

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(selftest ? .accessory : .regular)
        NSApp.applicationIconImage = iconImage(512)

        let files = loadResources()
        guard files["/index.html"] != nil else {
            fatal("The app bundle is incomplete — index.html is missing from Resources/www.")
            return
        }
        handler = ResourceHandler(files)

        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()                    // documents persist here
        cfg.setURLSchemeHandler(handler, forURLScheme: kScheme)
        cfg.userContentController.addUserScript(
            WKUserScript(source: bridgeJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.userContentController.add(self, name: "gt")

        web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        if #available(macOS 13.3, *) { web.isInspectable = true }

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1360, height: 880),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Pyramid Principle"
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 720, height: 560)
        window.contentView = web
        window.setFrameAutosaveName("GTMain")
        window.center()
        if !selftest { window.makeKeyAndOrderFront(nil) }

        buildMenu()
        web.load(URLRequest(url: URL(string: kHome)!))
        if !selftest { NSApp.activate(ignoringOtherApps: true) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    /// `--selftest` proves the page really rendered in this WKWebView, that
    /// localStorage survives on the gt:// origin, that the bundled fonts
    /// resolved, and that the downloads bridge answered. Exits 0.
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
        guard selftest else { return }
        let probe = """
        (function () {
          var ls = 'blocked';
          try { localStorage.setItem('__gt', '1');
                ls = localStorage.getItem('__gt') === '1' ? 'ok' : 'bad';
                localStorage.removeItem('__gt'); } catch (e) { ls = 'threw'; }
          var fonts = 'none';
          try { if (document.fonts) fonts = 'faces:' + document.fonts.size; } catch (e) {}
          return JSON.stringify({
            title: document.title,
            origin: location.origin,
            steps: document.querySelectorAll('.step').length,
            views: document.querySelectorAll('.view').length,
            keyline: document.querySelectorAll('.row[data-depth="0"]').length,
            branches: document.querySelectorAll('.dcard').length,
            score: (document.getElementById('scoreVal') || {}).textContent,
            pound: document.body.textContent.indexOf('£14.2m') > -1,
            curly: document.body.textContent.indexOf('’') > -1,
            localStorage: ls, fonts: fonts,
            hasClaude: typeof window.claude === 'object'
          });
        })()
        """
        w.evaluateJavaScript(probe) { res, err in
            print(err.map { "PROBE ERROR: \($0)" } ?? (res as? String ?? "no result"))
            w.callAsyncJavaScript(
                "const d = await window.claude.use('downloads'); return (d && typeof d.save === 'function') ? 'downloads bridge: ok' : 'downloads bridge: null';",
                arguments: [:], in: nil, in: .page) { r2 in
                    switch r2 {
                    case .success(let v): print(v as? String ?? "bridge: no value")
                    case .failure(let e): print("bridge error: \(e)")
                    }
                    exit(0)
                }
        }
    }

    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) {
        fatal("The page could not be loaded: \(e.localizedDescription)")
    }

    /// Real websites open in the user's browser, not inside the app.
    func webView(_ w: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let u = action.request.url, action.navigationType == .linkActivated, u.scheme != kScheme {
            NSWorkspace.shared.open(u)
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }

    func userContentController(_ c: WKUserContentController, didReceive msg: WKScriptMessage) {
        guard let d = msg.body as? [String: Any], d["op"] as? String == "save",
              let id = d["id"] as? Int, let name = d["filename"] as? String,
              let text = d["data"] as? String else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] resp in
            var ok = false, code = "declined"
            if resp == .OK, let url = panel.url {
                do { try text.write(to: url, atomically: true, encoding: .utf8); ok = true }
                catch { code = "bad_request" }
            }
            self?.web.evaluateJavaScript("window.__gtResolve(\(id), \(ok), '\(code)')")
        }
    }

    func fatal(_ msg: String) {
        let a = NSAlert()
        a.messageText = "Pyramid Principle could not start"
        a.informativeText = msg
        a.runModal()
        NSApp.terminate(nil)
    }

    // Standard menus, so ⌘Q / ⌘W / copy / paste / zoom behave natively.
    func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Pyramid Principle",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Pyramid Principle",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Pyramid Principle",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem(); main.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu

        let editItem = NSMenuItem(); main.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        for (t, s, k) in [("Undo", "undo:", "z"), ("Redo", "redo:", "Z"), ("Cut", "cut:", "x"),
                          ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            if t == "Cut" || t == "Undo" { editMenu.addItem(.separator()) }
            editMenu.addItem(withTitle: t, action: Selector(s), keyEquivalent: k)
        }
        editItem.submenu = editMenu

        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Actual Size", action: #selector(zoomReset), keyEquivalent: "0")
        viewMenu.addItem(withTitle: "Zoom In", action: #selector(zoomIn), keyEquivalent: "+")
        viewMenu.addItem(withTitle: "Zoom Out", action: #selector(zoomOut), keyEquivalent: "-")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Reload", action: #selector(reload), keyEquivalent: "r")
        viewMenu.addItem(withTitle: "Enter Full Screen",
                         action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        viewItem.submenu = viewMenu

        NSApp.mainMenu = main
    }

    @objc func zoomIn()    { web.pageZoom = min(web.pageZoom + 0.1, 2.5) }
    @objc func zoomOut()   { web.pageZoom = max(web.pageZoom - 0.1, 0.5) }
    @objc func zoomReset() { web.pageZoom = 1.0 }
    @objc func reload()    { web.reload() }
}

// MARK: - Entry ──────────────────────────────────────────────────────────────

if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--emit-iconset" {
    emitIconset(CommandLine.arguments[2])
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
