#!/usr/bin/env node
'use strict';
/* Report the live state of a GitHub repository through the public API: size, tags,
   releases (and their assets), recent commits and the top-level tree.

   Why: the local clone only shows what has been fetched, and this project's remote
   has two merged histories plus release assets — the numbers matter when deciding
   how to clean it up.

   node work/tools/github_state.js [owner/repo]
*/
const REPO = process.argv[2] || 'xiaochong3432/TravelFrog-offline';

async function api(path) {
  const res = await fetch('https://api.github.com' + path, {
    headers: {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'frog-offline-repo-audit',
    },
  });
  if (!res.ok) return { error: res.status + ' ' + res.statusText };
  return res.json();
}

const mb = (kb) => (kb / 1024).toFixed(1) + ' MB';

(async () => {
  const repo = await api('/repos/' + REPO);
  if (repo.error) {
    console.log('repo lookup failed:', repo.error);
    process.exit(1);
  }
  console.log('=== ' + repo.full_name + ' ===');
  console.log('  default branch :', repo.default_branch);
  console.log('  size (API)     :', mb(repo.size), '  (GitHub 只算默认分支的对象)');
  console.log('  visibility     :', repo.visibility, '| forks:', repo.forks_count,
    '| stars:', repo.stargazers_count, '| issues:', repo.open_issues_count);
  console.log('  created/pushed :', repo.created_at, '/', repo.pushed_at);
  console.log('  license        :', repo.license ? repo.license.spdx_id : '(none)');

  const tags = await api('/repos/' + REPO + '/tags?per_page=20');
  console.log('\n=== tags (' + (Array.isArray(tags) ? tags.length : '?') + ') ===');
  if (Array.isArray(tags)) {
    for (const t of tags) console.log('  %s  %s', t.name.padEnd(12), t.commit.sha.slice(0, 10));
  }

  const rel = await api('/repos/' + REPO + '/releases?per_page=20');
  console.log('\n=== releases (' + (Array.isArray(rel) ? rel.length : '?') + ') ===');
  let assetTotal = 0;
  if (Array.isArray(rel)) {
    for (const r of rel) {
      console.log('  %s  %s  assets=%d  %s',
        r.tag_name.padEnd(10), (r.name || '').slice(0, 28).padEnd(28),
        r.assets.length, r.published_at);
      for (const a of r.assets) {
        assetTotal += a.size;
        console.log('       - %-46s %s  downloads=%d', a.name, mb(a.size / 1024), a.download_count);
      }
    }
  }
  console.log('  release assets total: ' + mb(assetTotal / 1048576));

  const commits = await api('/repos/' + REPO + '/commits?per_page=10');
  console.log('\n=== recent commits ===');
  if (Array.isArray(commits)) {
    for (const c of commits) {
      console.log('  %s  %s  %s', c.sha.slice(0, 8),
        (c.commit.author.date || '').slice(0, 16),
        (c.commit.message || '').split('\n')[0].slice(0, 70));
    }
  }

  const tree = await api('/repos/' + REPO + '/contents/');
  console.log('\n=== top level ===');
  if (Array.isArray(tree)) {
    for (const e of tree) {
      console.log('  %-34s %-5s %s', e.name, e.type, e.size !== undefined ? e.size : '');
    }
  }
})().catch((e) => { console.log('failed:', e.message); process.exit(1); });
