import { SourceRuntime } from './runtime.mjs';
const $ = id => document.getElementById(id);
const BASE = 'https://cotool-music-proxy.cotool-music-proxy.workers.dev';
const ALLOWED = new Set(['search.kuwo.cn', 'songsearch.kugou.com', 'lxmusicapi.onrender.com']);
let token = '', connected = false, playSequence = 0;
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
  const response = await fetch(`${BASE}/__lx_proxy?url=${encodeURIComponent(target.href)}`, {
    method, headers: { Authorization: `Bearer ${token}`, 'X-LX-Proxy-Headers': JSON.stringify(Object.fromEntries(headers)) },
    body: method === 'POST' ? body : undefined,
    signal: AbortSignal.any([AbortSignal.timeout(20000), ...(signal ? [signal] : [])]),
  });
  const text = await response.text();
  let value; try { value = JSON.parse(text); } catch { value = text; }
  if (!response.ok) throw new Error(`请求失败（${response.status}）：${value?.error || '音源服务不可用'}`);
  return { statusCode: response.status, statusMessage: response.statusText, headers: Object.fromEntries(response.headers),
    url: response.headers.get('x-lx-upstream-url') || url, ok: response.ok, body: value };
}
const runtime = new SourceRuntime(http);
async function action(button, fn) { button.disabled = true; try { await fn(); } catch (error) { status(error.message, true); } finally { button.disabled = false; } }
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
  runtime.dispose(); connected = false; token = $('token').value.trim();
  if (!token) throw new Error('请输入访问口令');
  status('正在连接…');
  // An authenticated HEAD validates credentials, unlike the public /health route.
  connected = true;
  try { await http('http://search.kuwo.cn/r.s', { method: 'HEAD' }); }
  catch (error) { connected = false; throw error; }
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
$('reference').onclick = () => action($('reference'), async () => {
  if (!connected) throw new Error('请先连接服务');
  status('正在从 GitHub 读取 music 目录中的参考音源…');
  const path = 'v260511/第一批次/HUIBQ音源.js'.split('/').map(encodeURIComponent).join('/');
  const response = await fetch(`https://api.github.com/repos/guoyue2010/lxmusic-/contents/${path}?ref=main`, { signal: AbortSignal.timeout(20000) });
  if (!response.ok) throw new Error('参考音源下载失败，请导入本地 .js 文件');
  const data = await response.json();
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
    const target = new URL('http://search.kuwo.cn/r.s');
    target.search = new URLSearchParams({ client:'kt',all:keyword,pn:'0',rn:'20',uid:'794762570',ver:'kwplayer_ar_9.2.2.1',vipver:'1',show_copyright_off:'1',newver:'1',ft:'music',cluster:'0',strategy:'2012',encoding:'utf8',rformat:'json',vermerge:'1',mobi:'1',issubtitle:'1' }).toString();
    const { body } = await http(target.href);
    if (!Array.isArray(body.abslist)) throw new Error('搜索接口返回了无法识别的数据');
    body.abslist.forEach((item, index) => {
      const button = document.createElement('button'); button.className = 'track';
      const number = document.createElement('span'); number.className = 'number'; number.textContent = String(index + 1).padStart(2, '0');
      const meta = document.createElement('span'); meta.className = 'meta';
      const title = document.createElement('strong'); title.textContent = item.SONGNAME || item.NAME || '未知歌曲';
      const artist = document.createElement('small'); artist.textContent = item.ARTIST || '未知歌手';
      const play = document.createElement('span'); play.className = 'play'; play.textContent = '▷';
      meta.append(title, artist); button.append(number, meta, play);
      button.onclick = () => action(button, async () => {
        const generation = ++playSequence;
        audio.pause(); status(`正在解析 ${title.textContent}…`);
        const quality = runtime.capabilities?.kw?.qualitys?.includes('128k') ? '128k' : runtime.capabilities?.kw?.qualitys?.[0];
        const url = await runtime.musicUrl({ songmid: String(item.MUSICRID).replace(/^MUSIC_/, ''), name: title.textContent, singer: artist.textContent, albumName: item.ALBUM || '', source: 'kw', types: [{type: quality}], _types: { [quality]: {} } }, quality);
        if (generation !== playSequence) return;
        audio.src = url; $('now').textContent = `${title.textContent} · ${artist.textContent}`;
        try { await audio.play(); status('正在播放'); } catch (error) {
          if (error.name === 'NotAllowedError') status('地址已解析，点击下方播放键开始播放。');
          else throw new Error('播放失败：音频地址可能失效或受浏览器限制');
        }
      });
      $('results').append(button);
    });
    status(body.abslist.length ? `${body.abslist.length} 首结果 · 点击歌曲播放` : '没有找到歌曲，换个关键词试试。');
  });
};
audio.addEventListener('error', () => status('音频加载失败：地址可能失效、限制访问或格式不受支持。', true));
audio.addEventListener('playing', () => status('正在播放'));
audio.addEventListener('pause', () => { if (audio.src && !audio.ended) status('已暂停'); });
audio.addEventListener('ended', () => status('播放结束，选一首继续听。'));
window.addEventListener('pagehide', () => runtime.dispose());
