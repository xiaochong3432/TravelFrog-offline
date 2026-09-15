
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// 仓库根：按本文件自身位置推导，不写死绝对路径
const PROJECT_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
// 从仍在线的官方 CDN 拉取「最后官方内容」中我们本地没有的部分。
// 判定标准：1088/patch.json 清单里 4168 条的 md5，与 work/run/web 逐文件 md5 比对，
// 只下载「我们这份 run/web 里不存在该 md5」的条目（= 新内容 + 被我们改过的文件的官方原版）。
import fs from 'node:fs';
import crypto from 'node:crypto';

const ROOT = PROJECT_ROOT;
const BASE = 'https://ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/';
const MANIFEST = path.join(ROOT, 'work', '_save_probe', 'picked', '1088', 'patch.json');
const WEB = path.join(ROOT, 'work', 'run', 'web');
const OUTDIR = path.join(ROOT, 'work', 'cdn', 'final1088');
const LOG = path.join(ROOT, 'work', 'logs', 'cdn_final1088.txt');
const CONC = 6;

fs.mkdirSync(OUTDIR, { recursive: true });
fs.mkdirSync(path.dirname(LOG), { recursive: true });
const logf = fs.createWriteStream(LOG, { flags: 'a' });
const log = (s) => { const line = `[${new Date().toISOString()}] ${s}`; console.log(line); logf.write(line + '\n'); };

const md5 = (p) => crypto.createHash('md5').update(fs.readFileSync(p)).digest('hex');

log('=== 开始：拉取 1088 清单中本地缺少的部分 ===');
const man0 = JSON.parse(fs.readFileSync(MANIFEST, 'utf8'));
const man = Object.fromEntries(Object.entries(man0).filter(([k]) => !k.startsWith('__')));
log(`清单条目 ${Object.keys(man).length} 条，合计 ${(Object.values(man).reduce((a, v) => a + (v['2'] || 0), 0) / 1048576).toFixed(1)} MB`);

// 1) 索引本地 run/web 的 md5
const have = new Set();
let scanned = 0;
for (const dir of [WEB]) {
  const stack = [dir];
  while (stack.length) {
    const d = stack.pop();
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) stack.push(p);
      else { try { have.add(md5(p)); scanned++; } catch { } }
    }
  }
}
log(`run/web 索引 ${scanned} 个文件，${have.size} 个不同 md5`);

// 2) 计算待下载清单
const todo = [];
let skipBytes = 0;
for (const [rel, v] of Object.entries(man)) {
  const [, ver, hash, size] = [0, v['0'], v['1'], v['2'] || 0];
  if (have.has(hash)) { skipBytes += size; continue; }
  const dest = path.join(OUTDIR, ver, ...rel.split('/'));
  if (fs.existsSync(dest) && md5(dest) === hash) continue;   // 已下过
  todo.push({ rel, ver, hash, size, dest });
}
log(`本地已有(同 md5): ${Object.keys(man).length - Object.keys(man).length + 0}`.replace(/.*/, `需下载 ${todo.length} 条，${(todo.reduce((a, x) => a + x.size, 0) / 1048576).toFixed(1)} MB；跳过 ${(skipBytes / 1048576).toFixed(1)} MB`));

let ok = 0, fail = 0, bytes = 0;
const failures = [];
let idx = 0;

async function worker(id) {
  while (true) {
    const i = idx++;
    if (i >= todo.length) return;
    const it = todo[i];
    const url = `${BASE}${it.ver}/${it.rel}`;
    let done = false;
    for (let attempt = 1; attempt <= 3 && !done; attempt++) {
      try {
        const ac = new AbortController();
        const t = setTimeout(() => ac.abort(), 60000);
        const r = await fetch(url, { signal: ac.signal });
        clearTimeout(t);
        if (!r.ok) throw new Error(`HTTP ${r.status}`);
        const buf = Buffer.from(await r.arrayBuffer());
        const got = crypto.createHash('md5').update(buf).digest('hex');
        if (got !== it.hash) throw new Error(`md5 mismatch got=${got} want=${it.hash} (${buf.length}B)`);
        fs.mkdirSync(path.dirname(it.dest), { recursive: true });
        fs.writeFileSync(it.dest, buf);
        ok++; bytes += buf.length; done = true;
        if (ok % 25 === 0 || ok === todo.length) log(`进度 ${ok + fail}/${todo.length}  ok=${ok} fail=${fail} ${(bytes / 1048576).toFixed(1)} MB`);
      } catch (e) {
        if (attempt === 3) { fail++; failures.push({ url, err: e.message }); log(`FAIL ${url} :: ${e.message}`); }
        else await new Promise((res) => setTimeout(res, 800 * attempt));
      }
    }
  }
}

const t0 = Date.now();
await Promise.all(Array.from({ length: CONC }, (_, i) => worker(i)));
log(`=== 完成：ok=${ok} fail=${fail} 用时 ${((Date.now() - t0) / 1000).toFixed(0)}s，下载 ${(bytes / 1048576).toFixed(1)} MB ===`);
if (failures.length) {
  fs.writeFileSync(path.join(OUTDIR, 'FAILURES.json'), JSON.stringify(failures, null, 1));
  log(`失败清单见 ${path.join(OUTDIR, 'FAILURES.json')}`);
}
// 存一份本次使用的清单与说明
fs.copyFileSync(MANIFEST, path.join(OUTDIR, 'patch.json'));
fs.writeFileSync(path.join(OUTDIR, 'README.txt'),
  `《旅行青蛙·中国之旅》官方热修内容 · 最终版 1088 · 缺失部分补档\n` +
  `==================================================\n\n` +
  `来源：${BASE}<版本目录>/<资源路径>（官方 CDN，拉取时仍在线）\n` +
  `清单：patch.json（1088 版，4168 条：路径 -> {0:版本目录, 1:md5, 2:大小}，官方 __version__=1088 / __mtime__=2026-02-10）\n` +
  `本目录只保存「本地 work/run/web 中不存在相同 md5」的条目（新内容 + 被离线补丁改过的文件的官方原版）。\n` +
  `每个文件下载后逐一对 patch.json 的 md5 做过校验；失败项会写入 FAILURES.json。\n` +
  `目录结构：<版本目录>/<原始资源路径>，与官方一致。\n`);
log('已写出 README.txt 与 patch.json');
logf.end();
