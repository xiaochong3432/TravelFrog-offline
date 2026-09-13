#!/usr/bin/env node
'use strict';
/* Predict what .gitignore will keep, so "how big is the repo going to be" is a
   measured number instead of a guess.

   node work/tools/git_scope_report.js */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const ig = fs.readFileSync(path.join(ROOT, '.gitignore'), 'utf8');
/* Only the ACTIVE patterns matter: a line starting with '#' is a comment. */
const patterns = ig.split(/\r?\n/)
  .map((l) => l.trim())
  .filter((l) => l && !l.startsWith('#'));

function toRe(p) {
  let s = p.replace(/[.+^${}()|[\]\\]/g, '\\$&');
  s = s.replace(/\*\*/g, '\u0000').replace(/\*/g, '[^/]*').replace(/\u0000/g, '.*');
  s = s.replace(/\?/g, '.');
  return new RegExp('^' + s + '(/.*)?$');
}
const rules = patterns.map((p) => {
  let pat = p.replace(/^\//, '');
  /* A trailing slash means "this directory and everything under it". */
  pat = pat.replace(/\/$/, '');
  return { src: p, re: toRe(pat) };
});

function ignored(rel) {
  const r = rel.split(path.sep).join('/');
  for (const rule of rules) {
    if (rule.re.test(r)) return rule.src;
    /* a bare directory name also covers anything under it */
    if (rule.re.test(r + '/')) return rule.src;
  }
  return null;
}

const byDir = new Map();
let keptFiles = 0;
let keptBytes = 0;
let dropFiles = 0;
let dropBytes = 0;
const dropped = new Map();

function walk(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, e.name);
    const rel = path.relative(ROOT, full);
    if (e.isDirectory()) {
      if (e.name === '.git' || e.name === '__pycache__') continue;
      walk(full);
      continue;
    }
    let st;
    try { st = fs.statSync(full); } catch (err) { continue; }
    const rule = ignored(rel);
    if (rule) {
      dropFiles += 1;
      dropBytes += st.size;
      const key = rule;
      const rec = dropped.get(key) || { n: 0, b: 0 };
      rec.n += 1; rec.b += st.size;
      dropped.set(key, rec);
      continue;
    }
    keptFiles += 1;
    keptBytes += st.size;
    const top = rel.split(path.sep).slice(0, 2).join('/');
    const rec = byDir.get(top) || { n: 0, b: 0 };
    rec.n += 1; rec.b += st.size;
    byDir.set(top, rec);
  }
}
walk(ROOT);

const mb = (b) => (b / 1024 / 1024).toFixed(1) + ' MB';
console.log('KEEP  ' + keptFiles + ' files / ' + mb(keptBytes));
console.log('IGNORE ' + dropFiles + ' files / ' + mb(dropBytes));
console.log('\ntop paths that would be committed:');
[...byDir.entries()].sort((a, b) => b[1].b - a[1].b).slice(0, 20).forEach(([k, v]) => {
  console.log('  ' + mb(v.b).padStart(9) + '  ' + String(v.n).padStart(6) + ' files  ' + k);
});
console.log('\nbiggest ignored groups:');
[...dropped.entries()].sort((a, b) => b[1].b - a[1].b).slice(0, 14).forEach(([k, v]) => {
  console.log('  ' + mb(v.b).padStart(9) + '  ' + String(v.n).padStart(6) + ' files  ' + k);
});
