#!/usr/bin/env node
'use strict';
/**
 * 仓库硬规矩检查器 —— 提交前（pre-commit）与 CI 都跑它。
 *
 * 硬规矩：
 *   1. 不含客户端原始美术/音频资源（resource/、work/cdn、根 web/ 等）
 *   2. 不含成品包与构建产物（*.apk / *.zip / *.aab / build 目录 / __pycache__ …）
 *   3. 不含任何本机绝对路径（旧工作区根、带用户名的个人目录、临时目录）
 *   4. 单文件 ≤ 5 MB；全部跟踪文件合计 ≤ 60 MB
 *
 *   node work/tools/staged_check.js            # 检查暂存区（pre-commit 用）
 *   node work/tools/staged_check.js --all      # 检查 HEAD 里的全部文件（CI 用）
 *
 * 退出码非 0 表示有问题；`git commit --no-verify` 可以绕过（不建议）。
 */
const { execFileSync } = require('child_process');

const SIZE_LIMIT = 5 * 1024 * 1024;
const BUDGET = 60 * 1024 * 1024;
const ALL = process.argv.includes('--all');
const QUIET = !process.argv.includes('--verbose');

/* ---------------------------------------------------------------- 规则表 */
const FORBIDDEN_PATHS = [
  [/^"?web\//, '根目录的 web/ 是成品运行时（含客户端美术），仓库里不放'],
  [/\/resource\//, 'resource/ 是客户端原始美术/音频，仓库里不放'],
  [/^"?work\/cdn\//, 'CDN 归档体积大且非代码，走外部归档'],
  [/^"?work\/run\/v3web\//, 'V3 载荷抽取目录是本地产物'],
  [/^"?work\/build\//, '打包中间产物'],
  [/^"?work\/shots\//, '验证截图'],
  [/^"?work\/portable-backup\//, '改写备份'],
  [/__pycache__\//, 'Python 字节码缓存'],
  [/\.(apk|aab|zip|mp4|dex|so|jar|eab)"?$/, '成品包 / 二进制产物'],
  [/\.(bak|tmp|orig)"?$|\.corrupt-\d+"?$/, '临时/备份文件'],
];
// dist/ 下的启动器与密钥、以及"特意保留的旧版客户端快照"是允许的
const ALLOW_BINARY = [/^"?dist\/[^/]*\.(exe|pem|pk8)"?$/, /^"?work\/pristine\/.*\.js"?$/,
                      /^"?work\/run\/web\/js\/main\.min\.js\.(orig|clean)"?$/,
                      /^"?work\/tools\/_browser_resolver\.js\.inc"?$/];

// 本机路径的判定片段（拼出来，免得本文件自己命中规则）
const MACHINE_MARKERS = [
  'h:' + '/' + 'ai' + '/' + 'frog',        // 旧工作区根（比较前把反斜杠归一成斜杠）
  'c:' + '/' + 'users' + '/',
  'appdata' + '/' + 'local' + '/' + 'temp',
];
const TEXT_EXT = /\.(py|js|mjs|ps1|cs|java|cmd|bat|md|txt|json|html|yml|yaml|xml|sh|inc|gradle|properties)"?$/;

function git(args, opts) {
  return execFileSync('git', args, Object.assign({
    encoding: 'utf8', maxBuffer: 256 * 1024 * 1024,
    stdio: ['ignore', 'pipe', 'ignore'],
  }, opts || {}));
}

/* ------------------------------------------------------- 取文件与体积清单 */
let entries = [];          // {path, sha, size}
if (ALL) {
  // git ls-tree -r -l HEAD: <mode> <type> <sha> <size>\t<path>
  const out = git(['ls-tree', '-r', '-l', 'HEAD']);
  for (const line of out.split('\n')) {
    if (!line.trim()) continue;
    const m = line.match(/^(\d+)\s+(\w+)\s+([0-9a-f]+)\s+(\d+|-)\t(.*)$/);
    if (!m || m[2] !== 'blob') continue;
    entries.push({ path: m[5], sha: m[3], size: parseInt(m[4] === '-' ? '0' : m[4], 10) });
  }
} else {
  // 暂存区：先拿路径+sha，再用一次 cat-file --batch-check 拿体积
  const staged = git(['diff', '--cached', '--name-only', '--diff-filter=ACMR'])
    .split('\n').filter(Boolean);
  if (staged.length) {
    const shas = git(['ls-files', '-s', '--'].concat(staged))
      .split('\n').filter(Boolean)
      .map((l) => { const m = l.match(/^\d+\s+([0-9a-f]+)\s+\d+\t(.*)$/); return m ? { sha: m[1], path: m[2] } : null; })
      .filter(Boolean);
    const check = execFileSync('git', ['cat-file', '--batch-check=%(objectname) %(objectsize)'], {
      input: shas.map((s) => s.sha).join('\n') + '\n',
      encoding: 'utf8', maxBuffer: 64 * 1024 * 1024,
      stdio: ['pipe', 'pipe', 'ignore'],
    });
    const sizes = new Map();
    for (const line of check.split('\n')) {
      const m = line.match(/^([0-9a-f]+)\s+(\d+)$/);
      if (m) sizes.set(m[1], parseInt(m[2], 10));
    }
    entries = shas.map((s) => ({ path: s.path, sha: s.sha, size: sizes.get(s.sha) || 0 }));
  }
}

/* ------------------------------------------------------------ 逐条检查 */
const problems = [];
let total = 0;
const tooBig = [];
for (const e of entries) {
  const rel = e.path.replace(/\\/g, '/');
  const allowed = ALLOW_BINARY.some((a) => a.test(rel));
  total += e.size;

  for (const [rx, why] of FORBIDDEN_PATHS) {
    if (rx.test(rel) && !allowed) problems.push({ kind: '路径', file: rel, why });
  }
  if (e.size > SIZE_LIMIT) {
    problems.push({ kind: '体积', file: rel, why: (e.size / 1048576).toFixed(1) + ' MB > 5 MB 上限' });
    tooBig.push(rel);
  }
}

/* --------------------------- 内容检查：本机绝对路径（只查文本、且 ≤5MB） */
const textEntries = entries.filter((e) => e.size > 0 && e.size <= SIZE_LIMIT
  && (TEXT_EXT.test(e.path) || !e.path.includes('.')));
if (textEntries.length) {
  const batch = execFileSync('git', ['cat-file', '--batch'], {
    input: textEntries.map((e) => e.sha).join('\n') + '\n',
    maxBuffer: 512 * 1024 * 1024,
    stdio: ['pipe', 'pipe', 'ignore'],
  });
  // 解析 --batch 输出：<sha> <type> <size>\n<content>\n
  let off = 0;
  for (const e of textEntries) {
    const nl = batch.indexOf(0x0a, off);
    if (nl < 0) break;
    const header = batch.slice(off, nl).toString('utf8');
    const m = header.match(/^([0-9a-f]+)\s+blob\s+(\d+)$/);
    if (!m) break;
    const size = parseInt(m[2], 10);
    const body = batch.slice(nl + 1, nl + 1 + size).toString('latin1');
    off = nl + 1 + size + 1;
    const low = body.replace(/\\/g, '/').toLowerCase();
    for (const marker of MACHINE_MARKERS) {
      if (low.includes(marker)) {
        if (!ALLOW_BINARY.some((a) => a.test(e.path.replace(/\\/g, '/')))) {
          problems.push({ kind: '本机路径', file: e.path, why: '内容含 "' + marker + '"' });
        }
        break;
      }
    }
  }
}

/* ---------------------------------------------------------------- 报告 */
const scope = ALL ? 'HEAD 里的全部文件' : '本次暂存的文件';
if (!problems.length) {
  console.log('仓库规矩检查通过：' + scope + ' ' + entries.length
    + ' 个，合计 ' + (total / 1048576).toFixed(1) + ' MB');
} else {
  console.error('仓库规矩检查未通过：' + scope + ' ' + entries.length + '\n');
  const byKind = {};
  for (const p of problems) (byKind[p.kind] = byKind[p.kind] || []).push(p);
  for (const kind of Object.keys(byKind)) {
    const list = byKind[kind];
    console.error('【' + kind + '】' + list.length + ' 项');
    for (const p of list.slice(0, QUIET ? 15 : 100)) {
      console.error('   ' + p.file + '\n      → ' + p.why);
    }
    if (list.length > (QUIET ? 15 : 100)) {
      console.error('   …还有 ' + (list.length - (QUIET ? 15 : 100)) + ' 项');
    }
  }
  console.error('\n补救：');
  console.error('   git rm -r --cached <路径>          # 从索引移除但保留本地文件');
  console.error('   把对应模式加进 .gitignore，避免再次被 add');
  console.error('   node work/tools/staged_check.js --all   # 复核');
}

if (ALL && total > BUDGET) {
  console.error('\n体积超预算：跟踪体积 ' + (total / 1048576).toFixed(1) + ' MB > '
    + (BUDGET / 1048576).toFixed(0) + ' MB —— 请把大文件移出仓库（见 CONTRIBUTING.md）。');
  process.exit(1);
}
process.exit(problems.length ? 1 : 0);
