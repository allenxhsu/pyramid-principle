#!/usr/bin/env node
/*
 * check-inline — does governing-thought.html still agree with ../ui-kit?
 *
 * This app is one self-contained file served two ways (a Claude artifact, and a
 * macOS app behind the gt:// scheme), so it cannot link ../ui-kit the way the
 * Metropolis and IDEF0 apps do: the kit is copied in. A copy silently rots, so
 * every inlined region is delimited by markers naming where it came from:
 *
 *     @inline source=<path> commit=<sha> mode=copy|port
 *     ... the inlined region ...
 *     @inline-end
 *
 *   mode=copy  the region must be byte-identical to the source file today.
 *              Anything else is drift: re-copy the source, or if the block was
 *              edited here deliberately, move that edit into ../ui-kit.
 *
 *   mode=port  the region is a rewrite, not a copy — the theme runtime is
 *              ui-kit/js/theme.js rebuilt as plain functions because this page
 *              has no module loader. Bytes cannot match, so the marker carries
 *              `hash=<8 hex>` of the source it was ported from, and the check is
 *              whether that content has changed at all. A hash rather than a
 *              commit because these kits are edited in place: a commit stamp
 *              passes happily while the working file has already moved on.
 *
 * No dependencies, no build step. Exits non-zero if anything drifted.
 *
 *     node scripts/check-inline.mjs          report
 *     node scripts/check-inline.mjs --fix    re-copy drifted mode=copy blocks
 *                                            and restamp every commit
 */

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const page = join(root, 'governing-thought.html');
const fix = process.argv.includes('--fix');

const MARK = /^([^\n]*?)@inline source=(\S+) commit=(\S+) mode=(copy|port)([^\n]*)$/gm;
/** First 8 hex of the source's sha256 — what a port is pinned to. */
const digest = text => createHash('sha256').update(text).digest('hex').slice(0, 8);
/* A block embedded in a <script> cannot contain the substring that ends one, so
   `escape=script` on the marker means the one occurrence was written `<\\/script>`.
   The checker reverses it before diffing, so this stays a real byte comparison. */
const unescapeScript = s => s.replaceAll('<\\/script>', '</script>');
const END = /^.*@inline-end.*$/gm;

const red = s => `\x1b[31m${s}\x1b[0m`;
const green = s => `\x1b[32m${s}\x1b[0m`;
const dim = s => `\x1b[2m${s}\x1b[0m`;

/** Where a source path resolves to, and which repo owns it. */
function sourceFile(rel) {
  // paths are written repo-relative from ClaudWorkSpace, e.g. ui-kit/css/base.css
  return join(root, '..', rel);
}
function repoOf(rel) {
  return join(root, '..', rel.split('/')[0]);
}
/*
 * What git knows about a source right now.
 *
 * `dirty` is the one that matters and the one a first version missed: these
 * kits are edited in place, so a file can be modified or untracked while
 * `git log` still happily reports the last commit that touched it. A port
 * checked only against that commit passes while the source it was ported from
 * has already changed underneath it — a false pass, which is worse than no
 * check. A copy is safe either way because the bytes are compared directly.
 */
function sourceState(rel) {
  const repo = repoOf(rel);
  const inner = rel.split('/').slice(1).join('/');
  const git = (...args) => execFileSync('git', ['-C', repo, ...args], { encoding: 'utf8' });
  try {
    const status = git('status', '--porcelain', '--', inner).trim();
    if (status.startsWith('??')) return { commit: 'untracked', dirty: true, tracked: false };
    const commit = git('log', '-1', '--format=%h', '--', inner).trim();
    return { commit: commit || 'untracked', dirty: status.length > 0, tracked: true };
  } catch {
    return { commit: null, dirty: false, tracked: true };
  }
}

let html = readFileSync(page, 'utf8');
const blocks = [];
for (const m of html.matchAll(MARK)) {
  const open = m[0];
  const from = m.index + open.length + 1;              // first char after the marker line
  END.lastIndex = from;
  const close = END.exec(html);
  if (!close) {
    console.error(red(`  unterminated @inline block for ${m[2]}`));
    process.exit(2);
  }
  blocks.push({
    source: m[2], commit: m[3], mode: m[4], escaped: /escape=script/.test(m[5] || ''),
    hash: (/hash=([0-9a-f]+)/.exec(m[5] || '') || [])[1] || null,
    markerLine: open,
    body: html.slice(from, close.index).replace(/\n$/, ''),
    bodyStart: from, bodyEnd: close.index,
    line: html.slice(0, m.index).split('\n').length,
  });
}

if (!blocks.length) {
  console.error(red('no @inline blocks found — has the page been restructured?'));
  process.exit(2);
}

/* A marker this regex cannot parse used to be skipped in silence, which is the
   one thing a drift checker must never do: the block stops being checked and
   nothing says so. Count the markers in the file and insist they all parsed. */
const declared = (html.match(/@inline source=/g) || []).length;
if (declared !== blocks.length) {
  console.error(red(`${declared} @inline markers in the page but only ${blocks.length} parsed`) +
    '\n  a malformed marker is unchecked — every one needs ' +
    'source=<path> commit=<sha|untracked> mode=copy|port');
  process.exit(2);
}

let bad = 0, fixed = 0;
const edits = [];

for (const b of blocks) {
  const file = sourceFile(b.source);
  const label = `${b.source} ${dim('(line ' + b.line + ')')}`;

  if (!existsSync(file)) {
    console.log(`${red('MISSING')}  ${label}\n          source file does not exist`);
    bad++;
    continue;
  }

  const { commit: now, dirty } = sourceState(b.source);

  if (b.mode === 'port') {
    /*
     * A port is a rewrite, so its bytes can never match. What it is pinned to
     * is the source's CONTENT — a hash, not a commit: these kits are edited in
     * place, and a commit stamp says nothing about a file that has been
     * modified since. The hash is the same question asked honestly: has the
     * thing I ported from changed at all, committed or not?
     */
    const h = digest(readFileSync(file, 'utf8'));
    if (!b.hash) {
      console.log(`${red('UNPINNED')} ${label}\n` +
        `          a port needs hash=<8 hex> to be checkable; run --fix to pin it`);
      bad++;
      if (fix) edits.push({ from: b.markerLine, to: `${b.markerLine.replace(/\s*\*\/\s*$/, '')} hash=${h} */` });
    } else if (h !== b.hash) {
      console.log(`${red('MOVED')}    ${label}\n` +
        `          ported from ${b.hash}, source is now ${h}${dirty ? ' (uncommitted)' : ''}\n` +
        `          re-read the source, update the port, then restamp with --fix`);
      bad++;
      if (fix) edits.push({ from: b.markerLine, to: b.markerLine.replace(`hash=${b.hash}`, `hash=${h}`) });
    } else {
      console.log(`${green('ok')}       ${label} ${dim('port @ ' + h + (dirty ? ', source uncommitted' : ''))}`);
    }
    continue;
  }

  const want = readFileSync(file, 'utf8').replace(/\n+$/, '');
  const have = b.escaped ? unescapeScript(b.body) : b.body;
  if (have === want) {
    if (now && now !== b.commit) {
      // Content matches but the recorded commit is stale — restamp, don't fail.
      if (fix) {
        edits.push({ from: b.markerLine, to: b.markerLine.replace(`commit=${b.commit}`, `commit=${now}`) });
        fixed++;
      }
      console.log(`${green('ok')}       ${label} ${dim('content matches; commit stamp ' + b.commit + ' → ' + now)}`);
    } else {
      console.log(`${green('ok')}       ${label} ${dim('copy @ ' + b.commit + (dirty ? ', source uncommitted' : ''))}`);
    }
    continue;
  }

  // Real drift.
  const a = have.split('\n'), c = want.split('\n');
  let first = 0;
  while (first < a.length && first < c.length && a[first] === c[first]) first++;
  console.log(`${red('DRIFT')}    ${label}\n` +
    `          inlined ${a.length} lines, source ${c.length} lines; first differs at ${first + 1}\n` +
    `          ${dim('inlined:')} ${JSON.stringify((a[first] ?? '').slice(0, 72))}\n` +
    `          ${dim('source :')} ${JSON.stringify((c[first] ?? '').slice(0, 72))}`);
  bad++;
  if (fix) {
    edits.push({ replaceRange: [b.bodyStart, b.bodyEnd], with: want + '\n' });
    if (now && now !== b.commit)
      edits.push({ from: b.markerLine, to: b.markerLine.replace(`commit=${b.commit}`, `commit=${now}`) });
    fixed++;
  }
}

if (fix && edits.length) {
  // Ranges first, back to front, so earlier offsets stay valid.
  for (const e of edits.filter(e => e.replaceRange).sort((x, y) => y.replaceRange[0] - x.replaceRange[0]))
    html = html.slice(0, e.replaceRange[0]) + e.with + html.slice(e.replaceRange[1]);
  for (const e of edits.filter(e => e.from)) html = html.replace(e.from, e.to);
  writeFileSync(page, html);
  console.log(`\n${green('fixed')} ${fixed} block(s) — re-run without --fix to confirm`);
  process.exit(0);
}

console.log();
if (bad) {
  console.log(red(`${bad} block(s) drifted`) + dim('  — run with --fix to re-copy, or move the edit into ../ui-kit'));
  process.exit(1);
}
console.log(green(`all ${blocks.length} inlined blocks agree with their sources`));
