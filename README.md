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

## Data out

The document is also a graph: **Export → Graph (JSON-LD)** or **Triples
(CSV)** render every idea as a typed entity and every relationship — including
`derivedFrom`, the link from a promoted claim back to the analysis branch that
produced it — as a typed edge. Ids are creation-ordered and namespaced
(`urn:pyramid:<documentId>:<kind>:<nodeId>`) so documents merge without
collision. See **Guide → Data out** in the app for the full vocabulary.
