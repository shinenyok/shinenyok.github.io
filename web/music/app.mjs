import { SourceRuntime } from './runtime.mjs';
import { requestText, normalizeToken, responseError } from './network.mjs';
import { shuffle, moveIndex, parseQQHotChart, parseKugouHotChart, chartPlayScore } from './charts.mjs';
const $ = id => document.getElementById(id);
const BASE = 'https://api.shineyoki.top';
const ALLOWED = new Set(['search.kuwo.cn', 'songsearch.kugou.com', 'mobilecdnbj.kugou.com', 'u.y.qq.com', 'lxmusicapi.onrender.com']);
let token = '', connected = false, playSequence = 0, queue = [], queueIndex = -1;
const audio = $('audio');
const status = (text, error = false) => { $('status').textContent = text; $('status').className = error ? 'error' : ''; };
async function http(url, options = {}, signal) {
  if (!token || !connected) throw new Error('请先连接服务');
  if (options.binary) throw new Error('此音源需要暂未支持的二进制请求');
  const target = new URL(url);
  if (!ALLOWED.has(target.hostname) || !['https:', 'http:'].includes(target.protocol) || target.port || target.username || target.password) throw new Error(`音源域名尚未接入：${target.hostname}`);
  const method = (options.method || 'GET').toUpperCase();
  if (!['GET', 'POST', 'HEAD'].includes(method)) throw new Error('暂不支持该请求方法');
  const headers = new Headers(options.headers || {});
  let body = options.body;
  if (options.formData) throw new Error('暂不支持 multipart 音源请求');
  if (options.form) { body = new URLSearchParams(options.form).toString(); headers.set('content-type', 'application/x-www-form-urlencoded'); }
  else if (body && typeof body !== 'string') { body = JSON.stringify(body); headers.set('content-type', 'application/json'); }
  const { response, text } = await requestText(`${BASE}/__lx_proxy?url=${encodeURIComponent(target.href)}`, {
    method, headers: { Authorization: `Bearer ${token}`, 'X-LX-Proxy-Headers': JSON.stringify(Object.fromEntries(headers)) },
    body: method === 'POST' ? body : undefined,
    signal,
  });
  let value; try { value = JSON.parse(text); } catch { value = text; }
  if (!response.ok) throw new Error(responseError(response.status, value?.error));
  return { statusCode: response.status, statusMessage: response.statusText, headers: Object.fromEntries(response.headers),
    url: response.headers.get('x-lx-upstream-url') || url, ok: response.ok, body: value };
}
const runtime = new SourceRuntime(http);
async function action(button, fn) { button.disabled = true; try { await fn(); } catch (error) { status(error.message, true); } finally { button.disabled = false; } }
function updatePlayerButtons() {
  $('previous').disabled = queue.length < 2;
  $('next').disabled = queue.length < 2;
}
function trackTitle(track) { return track.title || track.SONGNAME || track.NAME || '未知歌曲'; }
function trackArtist(track) { return track.artist || track.ARTIST || '未知歌手'; }
function renderSearchResults(items) {
  $('results').replaceChildren();
  items.forEach((item, index) => {
    const button = document.createElement('button'); button.className = 'track';
    const number = document.createElement('span'); number.className = 'number'; number.textContent = String(index + 1).padStart(2, '0');
    const meta = document.createElement('span'); meta.className = 'meta';
    const title = document.createElement('strong'); title.textContent = trackTitle(item);
    const artist = document.createElement('small'); artist.textContent = trackArtist(item);
    const play = document.createElement('span'); play.className = 'play'; play.textContent = '▷';
    meta.append(title, artist); button.append(number, meta, play);
    button.onclick = () => {
      queue = items; queueIndex = index; updatePlayerButtons();
      void playQueueIndex(index);
    };
    $('results').append(button);
  });
}
function searchUrl(keyword) {
  const target = new URL('https://search.kuwo.cn/r.s');
  target.search = new URLSearchParams({ client:'kt',all:keyword,pn:'0',rn:'20',uid:'794762570',ver:'kwplayer_ar_9.2.2.1',vipver:'1',show_copyright_off:'1',newver:'1',ft:'music',cluster:'0',strategy:'2012',encoding:'utf8',rformat:'json',vermerge:'1',mobi:'1',issubtitle:'1' }).toString();
  return target.href;
}
async function matchChartTrack(track) {
  const { body } = await http(searchUrl(`${track.title} ${track.artist}`));
  const candidates = Array.isArray(body.abslist) ? body.abslist : [];
  const best = candidates.map(item => ({ item, score: chartPlayScore(track, item) })).sort((a, b) => b.score - a.score)[0];
  if (!best?.score || !best.item.MUSICRID) throw new Error(`酷我暂未找到「${track.title}」的可播放版本`);
  return best.item;
}
async function playQueueIndex(index) {
  if (!queue.length) return false;
  queueIndex = index; updatePlayerButtons();
  const track = queue[queueIndex];
  const title = trackTitle(track), artist = trackArtist(track);
  const generation = ++playSequence;
  audio.pause(); status(`正在解析 ${title}…`);
  try {
    const item = track.MUSICRID ? track : await matchChartTrack(track);
    if (generation !== playSequence) return false;
    const quality = runtime.capabilities?.kw?.qualitys?.includes('128k') ? '128k' : runtime.capabilities?.kw?.qualitys?.[0];
    const url = await runtime.musicUrl({ songmid: String(item.MUSICRID).replace(/^MUSIC_/, ''), name: item.SONGNAME || item.NAME || title, singer: item.ARTIST || artist, albumName: item.ALBUM || '', source: 'kw', types: [{type: quality}], _types: { [quality]: {} } }, quality);
    if (generation !== playSequence) return false;
    audio.src = url; $('now').textContent = `${title} · ${artist}`;
    try { await audio.play(); status('正在播放'); } catch (error) {
      if (error.name === 'NotAllowedError') status('地址已解析，点击下方播放键开始播放。');
      else throw new Error('播放失败：音频服务器可能不支持 HTTPS，或地址已失效');
    }
    return true;
  } catch (error) { if (generation === playSequence) status(error.message, true); return false; }
}
function moveQueue(direction) {
  if (queue.length < 1) return;
  const current = queueIndex < 0 ? (direction > 0 ? -1 : 0) : queueIndex;
  void playQueueIndex(moveIndex(current, direction, queue.length));
}
async function tryRandomQueue(tracks, source) {
  queue = shuffle(tracks); queueIndex = -1; updatePlayerButtons();
  const attempts = Math.min(queue.length, 5);
  for (let i = 0; i < attempts; i++) {
    const index = moveIndex(queueIndex, 1, queue.length);
    if (await playQueueIndex(index)) {
      status(`正在随机播放${source}（${trackTitle(queue[index])}）`);
      return true;
    }
  }
  return false;
}
$('close').onclick = () => parent.postMessage('music:close', location.origin);
document.addEventListener('keydown', e => { if (e.key === 'Escape') $('close').click(); });
$('tokenFile').onchange = async e => {
  const file = e.target.files[0]; if (!file) return;
  try { if (file.size > 4096) throw new Error('口令文件过大'); const value = (await file.text()).match(/^PROXY_TOKEN=(.+)$/m)?.[1]?.trim();
    if (!value) throw new Error('未找到 PROXY_TOKEN'); $('token').value = value; status('口令已读取，请点击连接服务。');
  } catch (error) { status(error.message, true); } finally { e.target.value = ''; }
};
$('token').oninput = () => { connected = false; token = ''; runtime.dispose(); $('sourceLabel').textContent = '未连接'; };
$('connect').onclick = () => action($('connect'), async () => {
  runtime.dispose(); connected = false; $('sourceLabel').textContent = '未连接'; token = normalizeToken($('token').value);
  if (!token) throw new Error('请输入访问口令');
  status('正在连接…');
  // Validate only this service and its token; no dependency on a music platform.
  const { response, text } = await requestText(`${BASE}/session`, { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) throw new Error(responseError(response.status));
  if (JSON.parse(text).ok !== true) throw new Error('服务返回异常，请稍后再试');
  connected = true;
  $('sourceLabel').textContent = '服务已连接'; status('服务已连接，请加载参考音源或导入脚本。');
});
async function loadSource(script, name) {
  if (!connected) throw new Error('请先连接服务');
  ++playSequence; status('正在初始化音源…');
  await runtime.load(script, name);
  $('sourceLabel').textContent = name;
  $('settings').open = false;
  status('音源已就绪，搜索一首歌试试。');
}
$('random').onclick = () => action($('random'), async () => {
  if (!connected) throw new Error('请先连接服务');
  if (!runtime.capabilities?.kw?.actions?.includes('musicUrl')) throw new Error('请先加载支持酷我的音源');
  status('正在读取 QQ 音乐热歌榜…');
  let tracks, source, qqError;
  try {
    const payload = { toplist: { module: 'musicToplist.ToplistInfoServer', method: 'GetDetail', param: { topid: 26, num: 100 } }, comm: { uin: 0, format: 'json', ct: 20, cv: 1859 } };
    const { body } = await http('https://u.y.qq.com/cgi-bin/musicu.fcg', { method: 'POST', headers: { 'content-type': 'application/json', referer: 'https://y.qq.com/' }, body: JSON.stringify(payload) });
    tracks = parseQQHotChart(body); source = 'QQ 音乐热歌榜';
    if (!tracks.length) throw new Error('QQ 榜单没有返回歌曲');
  } catch (error) {
    // Keep the primary error for a useful final message if the fallback also fails.
    tracks = []; source = ''; qqError = error;
  }
  if (tracks.length) {
    status(`已从${source}随机选歌，正在匹配播放源…`);
    if (await tryRandomQueue(tracks, source)) return;
    if (source === 'QQ 音乐热歌榜') qqError = new Error('QQ 榜单歌曲暂未匹配到可播放版本');
  }
  status('QQ 榜单暂不可用，正在尝试酷狗 TOP500…');
  const target = new URL('https://mobilecdnbj.kugou.com/api/v3/rank/song');
  target.search = new URLSearchParams({ version: '9108', ranktype: '1', plat: '0', pagesize: '100', area_code: '1', page: '1', rankid: '8888', with_res_tag: '0', show_portrait_mv: '1' }).toString();
  const { body } = await http(target.href);
  tracks = parseKugouHotChart(body);
  if (!tracks.length) throw new Error(`QQ 榜单${qqError ? '和' : ''}酷狗热歌榜都没有可播放歌曲`);
  if (!await tryRandomQueue(tracks, '酷狗 TOP500')) throw new Error('酷狗热歌榜歌曲也未匹配到可播放版本');
});
$('previous').onclick = () => moveQueue(-1);
$('next').onclick = () => moveQueue(1);
$('reference').onclick = () => action($('reference'), async () => {
  if (!connected) throw new Error('请先连接服务');
  status('正在从 GitHub 读取 music 目录中的参考音源…');
  const path = 'v260511/第一批次/HUIBQ音源.js'.split('/').map(encodeURIComponent).join('/');
  const { response, text } = await requestText(`https://api.github.com/repos/guoyue2010/lxmusic-/contents/${path}?ref=main`);
  if (!response.ok) throw new Error('参考音源下载失败，请导入本地 .js 文件');
  const data = JSON.parse(text);
  if (data.size > 1024 * 1024 || data.encoding !== 'base64') throw new Error('音源文件格式不支持');
  const script = new TextDecoder().decode(Uint8Array.from(atob(data.content.replace(/\s/g, '')), c => c.charCodeAt(0)));
  await loadSource(script, 'Huibq 参考音源');
});
$('sourceFile').onchange = async e => {
  const file = e.target.files[0]; if (!file) return;
  await action($('reference'), async () => { if (file.size > 1024 * 1024) throw new Error('脚本超过 1 MiB'); await loadSource(await file.text(), file.name); });
  e.target.value = '';
};
$('search').onsubmit = e => {
  e.preventDefault();
  action($('search').querySelector('button'), async () => {
    const keyword = $('keyword').value.trim(); if (!keyword) return;
    status('正在搜索…'); $('results').replaceChildren();
    const { body } = await http(searchUrl(keyword));
    if (!Array.isArray(body.abslist)) throw new Error('搜索接口返回了无法识别的数据');
    renderSearchResults(body.abslist);
    status(body.abslist.length ? `${body.abslist.length} 首结果 · 点击歌曲播放` : '没有找到歌曲，换个关键词试试。');
  });
};
audio.addEventListener('error', () => status('音频加载失败：服务器可能不支持 HTTPS、限制访问，或地址已失效。', true));
audio.addEventListener('playing', () => status('正在播放'));
audio.addEventListener('pause', () => { if (audio.src && !audio.ended) status('已暂停'); });
audio.addEventListener('ended', () => queue.length ? moveQueue(1) : status('播放结束，选一首继续听。'));
window.addEventListener('pagehide', () => runtime.dispose());
