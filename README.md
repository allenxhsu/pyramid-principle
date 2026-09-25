# Pyramid Principle

A guided workbench for Barbara Minto's Pyramid Principle: define a problem with
her R1/R2 gap framework, decompose it into a tested why/how logic tree, promote
what survives into a governing thought and key line, run 26 structural checks
against the argument, and export it — as a memo, an email, a slide outline, a
talk track, or a typed graph (JSON-LD / triples) for downstream analysis. A
twelve-lesson interactive walkthrough teaches the method using Minto's own
illustrations alongside a worked example.

One file, no build step: [`governing-thought.html`](governing-thought.html) is
the whole application — structure, the deterministic lint engine, the graph
export, everything.

## Running it

It's a single HTML file with no dependencies beyond two Google Fonts links.
Open it directly in a browser, or serve it:

```bash
python3 -m http.server 8000
```

Then open <http://localhost:8000/governing-thought.html>.

Storage falls back automatically: `localStorage` in a plain browser, or a
host-provided `db`/`downloads` capability when run inside an environment that
offers one (see the `window.claude` calls near the top of the `store` object).

## macOS app

[`mac/`](mac/) wraps the same file as a native, offline, universal (arm64 +
x86_64) `.app` — no Electron, no Node, ~1.6 MB installed. See
[mac/README.md](mac/README.md) for how it works and how to build it.

```bash
cd mac && ./build.sh
open "build/Pyramid Principle.app"
```

## Appearance

Pyramid shares its HUD skin with the other tools in
[ui-kit](https://github.com/kasinox/ui-kit) (Metropolis, Heptabase, IDEF0) —
Orbitron/Exo 2/Share Tech Mono, chamfered controls, corner-bracket panels.
Because this is a single bundled file with no access to a sibling folder at
runtime, it inlines a verbatim copy of the kit's CSS and a plain (non-module)
port of its theme runtime rather than linking the kit live; the canonical
adapter lives at `ui-kit/adapters/pyramid.css` in that repo and gets re-copied
in by hand when it changes. A picker in the top bar (▦) switches skin
(HUD/Classic), palette (Steel/Crystal/Chitin) and effects.

## What the checks enforce

The margin re-lints on every edit, scoped to whichever step you're on. Rules
span four groups — problem definition, analysis structure, the introduction,
and the pyramid's vertical/horizontal logic (one idea per box, three-to-five
per group, MECE siblings, a non-disputable situation, an ordering principle
for every group) — encoded as heuristics on English, not Minto's own published
checklist; dismiss any that misread a sentence. The **Guide** view documents
the full rule catalogue, the vocabulary, and the keyboard grammar.

## Storage: pyramid/1 records

The editor works on a nested document, but the **store works on records** — one
per pyramid, point, evidence item, question and reference, each with its own
`id` / `createdAt` / `updatedAt` / `deletedAt` / `origin`. The shape is
[`pyramid/1`](../MindMap/doc/09-pyramid-app.md); the record contract it has to
satisfy is [`../sync-server/docs/sync-protocol.md`](../sync-server/docs/sync-protocol.md).

`projectDoc()` flattens the document into records and `materialise()` rebuilds
it, so none of the editor, the checks or the walkthrough had to change to gain
this. Clocks are set by **diffing, not by the editor**: a record whose body is
unchanged keeps its old `updatedAt`, and a record that disappears from the
document is written back with `deletedAt` set rather than dropped. A save that
changes nothing therefore writes nothing, editing one point moves exactly one
clock, and a delete propagates as a tombstone instead of being resurrected by
the next device to sync.

Documents written before this are lifted into records once, on first load; the
old `governing-thought.docs.v1` key is left in place so the lift can be rolled
back by clearing `pyramid.records.v1`.

One departure from the spec is worth naming: `Point.group` stays an inline
field rather than becoming its own record. It is 1:1 with the point whose
children it describes, so it has no identity to sync and no separate clock, and
keeping it inline is what keeps the export readable by Metropolis.

**Export → JSON** writes a `pyramid/1` file. Pyramid's own state that the spec
has no room for — the problem definition, the decomposition tree, the dismissed
findings, the `derivedFrom` provenance map — travels under a single `x-pyramid`
key, so a strict reader can ignore it and a round-trip does not silently lose
the analysis. Tombstones are included: a deletion that did not travel would come
back from the next device to sync.

*Not yet built:* the sync client itself. `../sync-kit` does not exist, so there
is no third store backend and no Sync settings panel. The record shape, the
clocks, the tombstones and the per-device `origin` are all in place for it.

## Data out

The document is also a graph: **Export → Graph (JSON-LD)** or **Triples
(CSV)** render every idea as a typed entity and every relationship — including
`derivedFrom`, the link from a promoted claim back to the analysis branch that
produced it — as a typed edge. Ids are creation-ordered and namespaced
(`urn:pyramid:<documentId>:<kind>:<nodeId>`) so documents merge without
collision. See **Guide → Data out** in the app for the full vocabulary.

## On the Portal

`toolkit-app.json` is the whole contract: the Portal's `scripts/collect.mjs`
copies `governing-thought.html` to `build/apps/pyramid/index.html`, generates a
manifest, icons and a service worker from it, and injects a
`<meta name="toolkit-portal" content="pyramid">`. Served at `/pyramid/` on the
Portal's origin, the app configures itself — there is no URL to paste and no
token to store.

**Offline.** The two `fonts.googleapis.com` links were this page's only
third-party origin, and the Portal's worker caches nothing cross-origin: an
installed app would have opened in airplane mode with no typefaces. All six
families are now inlined as base64 woff2 — latin subset, only the weights this
page sets, one `@font-face` per file with a weight range where the family ships
a variable font. The page now references **no external origin at all**. That
costs about 518 KB, which a precached build pays once.

**Sync.** The records are the sync unit and always were; the engine is
`../sync-kit`, inlined as its IIFE. Two ways to reach a server, and the page
decides rather than the app:

| | |
| --- | --- |
| On the Portal | `SyncKit.portalApp()` sees the injected meta, `/auth/me` names the workspace, and the transport is same-origin with the session cookie. No token in the page — a second credential to leak for no benefit. The Sync panel says *Signed in via the toolkit* and offers nothing to configure. |
| Standalone | A server URL and a device token, kept under `pyramid.sync.*`. |

It pulls then pushes, on a timer, on focus, on reconnect and once an edit has
settled. Arriving changes are adopted immediately **unless the caret is in a
field** — swapping the document under a half-typed sentence loses the edit — in
which case they wait and the app says so.

**Storage prefixes.** Nine apps share one origin, so an unprefixed key is a
collision. Everything this app owns is `pyramid.*`: `pyramid.records`,
`pyramid.meta`, `pyramid.origin`, `pyramid.sync.*`. `ui-kit.*` stays shared on
purpose — that is how choosing a palette in one app changes all of them. The
one pre-prefix key, `governing-thought.docs.v1`, is read only when the app is
*not* on the Portal: off it, that is where the Mac app's real documents live;
on it, no such data can exist and an unprefixed read would be the collision
this rule is about.

## Keeping the inlined kit honest

This app cannot `<link>` [ui-kit](https://github.com/kasinox/ui-kit) the way
Metropolis and IDEF0 do — it is one bundled file served as an artifact and
behind `gt://`, with no sibling folder at runtime — so the kit is copied in.
Copies rot, so every inlined region is delimited by markers naming its source
and the commit it came from, and a script checks them:

```bash
node scripts/check-inline.mjs          # report drift
node scripts/check-inline.mjs --fix    # re-copy and restamp
```

`mode=copy` blocks — the kit's CSS, Pyramid's adapter, the sync-kit IIFE and
`<sc-portal-bar>` — must be byte-identical to their sources. `portal-bar.js`
carries `escape=script` because it contains the one substring that would end
the `<script>` it is embedded in; the checker reverses that single escape
before diffing, so it stays a real byte comparison.

The theme runtime is `mode=port` — `ui-kit/js/theme.js` rebuilt as plain
functions because this page has no module loader — so it is pinned to a
`hash=` of the source rather than a commit. A commit stamp was the first
design and it was wrong: these kits are edited in place, and a stamp passes
happily while the working file has already moved on. The hash asks the honest
question — has the thing I ported from changed at all, committed or not.

Edit the source in `../ui-kit` and re-run with `--fix`; never patch the inlined
blocks by hand.
