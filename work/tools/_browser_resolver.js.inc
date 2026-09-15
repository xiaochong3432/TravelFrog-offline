/* 浏览器可执行文件：$FROG_BROWSER 优先，否则按各系统的常见位置与 PATH 查找
   （Edge / Chrome；Windows、macOS、Linux 都试一遍），不再写死某一台机器的路径。 */
const EDGE = (function () {
  const fs = require('fs');
  const cp = require('child_process');
  const env = process.env.FROG_BROWSER;
  if (env && fs.existsSync(env)) return env;
  const cands = process.platform === 'win32' ? [
    'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
    'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
  ] : [
    '/usr/bin/microsoft-edge', '/usr/bin/microsoft-edge-stable',
    '/usr/bin/google-chrome', '/usr/bin/google-chrome-stable',
    '/usr/bin/chromium', '/usr/bin/chromium-browser',
    '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  ];
  for (const c of cands) { try { if (fs.existsSync(c)) return c; } catch (e) { /* skip */ } }
  for (const name of ['msedge', 'microsoft-edge', 'google-chrome', 'chromium']) {
    try {
      const out = cp.execSync((process.platform === 'win32' ? 'where ' : 'command -v ') + name,
        { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim().split(/\r?\n/)[0];
      if (out) return out;
    } catch (e) { /* not on PATH */ }
  }
  console.error('找不到 Edge/Chrome：请设置 FROG_BROWSER=<浏览器可执行文件路径>');
  process.exit(2);
})();
