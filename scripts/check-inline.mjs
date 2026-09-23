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
 *              has no module loader. Bytes cannot match, so instead the recorded
 *              commit is checked against the source's current commit: if the
 *              source has moved, the port needs a human to re-read it.
 *
 * No dependencies, no build step. Exits non-zero if anything drifted.
 *
 *     node scripts/check-inline.mjs          report
 *     node scripts/check-inline.mjs --fix    re-copy drifted mode=copy blocks
 *                                            and restamp every commit
 */

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const page = join(root, 'governing-thought.html');
const fix = process.argv.includes('--fix');

const MARK = /^([^\n]*?)@inline source=(\S+) commit=(\S+) mode=(copy|port)([^\n]*)$/gm;
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
function currentCommit(rel) {
  const repo = repoOf(rel);
  const inner = rel.split('/').slice(1).join('/');
  try {
    return execFileSync('git', ['-C', repo, 'log', '-1', '--format=%h', '--', inner],
      { encoding: 'utf8' }).trim();
  } catch {
    return null;
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
    source: m[2], commit: m[3], mode: m[4],
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

  const now = currentCommit(b.source);

  if (b.mode === 'port') {
    // A port cannot be diffed; what matters is whether the source moved under it.
    if (now && now !== b.commit) {
      console.log(`${red('MOVED')}    ${label}\n` +
        `          ported at ${b.commit}, source is now ${now}\n` +
        `          re-read the source and update the port, then restamp with --fix`);
      bad++;
    } else {
      console.log(`${green('ok')}       ${label} ${dim('port @ ' + b.commit)}`);
    }
    continue;
  }

  const want = readFileSync(file, 'utf8').replace(/\n+$/, '');
  if (b.body === want) {
    if (now && now !== b.commit) {
      // Content matches but the recorded commit is stale — restamp, don't fail.
      if (fix) {
        edits.push({ from: b.markerLine, to: b.markerLine.replace(`commit=${b.commit}`, `commit=${now}`) });
        fixed++;
      }
      console.log(`${green('ok')}       ${label} ${dim('content matches; commit stamp ' + b.commit + ' → ' + now)}`);
    } else {
      console.log(`${green('ok')}       ${label} ${dim('copy @ ' + b.commit)}`);
    }
    continue;
  }

  // Real drift.
  const a = b.body.split('\n'), c = want.split('\n');
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
