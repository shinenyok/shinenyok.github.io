// Use the same Kuwo search parameters as music/lib/features/search/search_repository.dart.
const base = process.argv[2];
const local = base === '--local';
const token = local ? 'local-probe-only' : process.env.PROXY_TOKEN;
if (!base || !token) {
  console.error('Usage: PROXY_TOKEN=<secret> npm run probe -- https://<worker>.workers.dev');
  process.exit(1);
}
const target = new URL('http://search.kuwo.cn/r.s');
target.search = new URLSearchParams({ client: 'kt', all: process.argv[3] || '晴天', pn: '0', rn: '3',
  uid: '794762570', ver: 'kwplayer_ar_9.2.2.1', vipver: '1', show_copyright_off: '1',
  newver: '1', ft: 'music', cluster: '0', strategy: '2012', encoding: 'utf8', rformat: 'json',
  vermerge: '1', mobi: '1', issubtitle: '1' }).toString();
const endpoint = new URL('/__lx_proxy', local ? 'http://localhost' : base);
endpoint.searchParams.set('url', target.href);
try {
  const req = new Request(endpoint, { headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(25000) });
  const response = local
    ? await (await import('../src/worker.mjs')).default.fetch(req, { PROXY_TOKEN: token, ALLOWED_HOSTS: 'search.kuwo.cn' })
    : await fetch(req);
  const data = await response.json();
  const tracks = data.abslist;
  if (!response.ok || !Array.isArray(tracks) || !tracks.length) {
    throw new Error(`HTTP ${response.status}; ${data.error || 'No search results; source compatibility not confirmed'}`);
  }
  console.log(`${local ? 'Local handler / live upstream' : 'Deployed proxy'} search OK: ${tracks.length} results`);
  console.log(tracks.map(track => ({ title: track.SONGNAME, artist: track.ARTIST, id: track.MUSICRID })));
  console.log('This validates search only, not source-script execution or audio playback.');
} catch (error) { console.error(error.message); process.exitCode = 1; }
