# Pyramid Principle — standalone macOS app

A real `.app` around the same single HTML file that runs as the artifact.
1.5 MB installed. No Electron, no Node, no Rust, no runtime to install.

```bash
./build.sh                      # → build/Pyramid Principle.app + PyramidPrinciple.dmg
open build/PyramidPrinciple.dmg # drag it across
```

The app is fully relocatable — put it in `/Applications`, on a USB stick,
anywhere. Nothing outside the bundle is referenced.

| | |
|---|---|
| Architectures | universal — arm64 and x86_64 |
| Minimum macOS | 11.0 Big Sur |
| Network | none. No sockets, no ports, no CDN |
| Installed size | 1.5 MB (1.0 MB as a `.dmg`) |

## How it works

`main.swift` is the whole app. Three things in it are load-bearing.

**Resources reach the WebView over a custom `gt://` scheme.** Not `file://`:
WKWebView refuses `localStorage` on `file://` origins, so every saved document
would vanish on quit. Not a loopback server either: that needs a port pinned
across launches (or the origin changes and storage is lost), can collide with
whatever else holds it, and can trip the firewall. `gt://app` has a fixed
origin for the life of the app and needs no network at all.

**The page is a fragment.** The Artifact host supplies the doctype, a charset
meta and a small reset at publish time. Standing alone it needs the same
skeleton — without the charset every curly quote and `£` becomes mojibake.
`build.sh` wraps it, so one source file serves both targets.

**A capability bridge.** The page asks for what it needs through
`claude.use(name)`. In the artifact the viewer answers; here the app does —
`downloads` gets a real `NSSavePanel`, everything else gets `null`, which is
what the page's own absence-handling expects. Export's Download button works
natively through the standard macOS save sheet.

Fonts (Newsreader, IBM Plex Sans, IBM Plex Mono) are fetched at build time and
bundled — both families are SIL Open Font License 1.1, which permits
redistribution inside an application. If the build machine is offline, the
build still succeeds and the app falls back to system faces.

Also: standard menus (⌘Q, ⌘W, copy/paste, zoom, reload), an icon drawn in Core
Graphics at build time, external links opened in the default browser, and
window position remembered between launches.

## Giving it to someone else

`build.sh` ad-hoc signs, which is enough to run on the Mac that built it. On
any other Mac, Gatekeeper will object because the app is not notarised. Two
ways past that:

**Sign it properly** (needs a paid Apple Developer account):

```bash
GT_SIGN_ID="Developer ID Application: Your Name (TEAMID)" ./build.sh
xcrun notarytool submit build/PyramidPrinciple.dmg \
  --apple-id you@example.com --team-id TEAMID --password APP_SPECIFIC_PW --wait
xcrun stapler staple build/PyramidPrinciple.dmg
```

**Or tell the recipient to bypass it** — right-click the app → Open → Open, or:

```bash
xattr -dr com.apple.quarantine "/Applications/Pyramid Principle.app"
```

## Where documents are stored

| | Artifact in a browser | This app |
|---|---|---|
| Storage | the artifact's `db` | `localStorage`, on this Mac |
| Syncs across devices | yes | no |
| Works offline | no | yes, completely |
| Claude can read them later | yes | no |

Separate stores — documents written in one do not appear in the other. Export →
JSON, then Import, moves one across. To wipe the app's data:
`rm -rf ~/Library/WebKit/com.governingthought.app`.

The bundle identifier stays `com.governingthought.app` even though the app was
renamed. It keys the WebKit data store, so changing it would orphan every
document already saved. It is internal and never shown.

## Verifying a build

```bash
"build/Pyramid Principle.app/Contents/MacOS/PyramidPrinciple" --selftest
```

Loads the page in a real off-screen WKWebView and reports what it found, then
exits 0:

```
{"title":"Pyramid Principle","origin":"gt://app","steps":5,"views":8,
 "keyline":3,"branches":10,"score":"94","pound":true,"curly":true,
 "localStorage":"ok","fonts":"faces:45","hasClaude":true}
downloads bridge: ok
```

`pound` and `curly` confirm UTF-8 survived the bundle; `fonts` confirms the
bundled faces resolved; `localStorage` confirms documents will persist.

Note: this will not run from `/tmp` on a machine that restricts launching GUI
apps from there. Test from `/Applications` or anywhere in your home folder.

## Updating it

The app bundles a copy of `../governing-thought.html` taken at build time. Edit
that file, re-run `./build.sh`, reinstall.
