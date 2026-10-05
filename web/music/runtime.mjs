// Executed in a blob Worker owned by an opaque sandboxed iframe, not the site origin.
export function sourceWorker() {
  const emit = self.postMessage.bind(self);
  let handler, initialized = false, sequence = 0;
  const callbacks = new Map();
  const unsupported = () => { throw new Error('此音源需要尚未适配的加密工具，请换一个音源'); };
  const buffer = {
    from(value, encoding = 'utf8') {
      if (typeof value !== 'string') return new Uint8Array(value);
      if (encoding === 'base64') return Uint8Array.from(atob(value), c => c.charCodeAt(0));
      if (encoding === 'hex') return Uint8Array.from(value.match(/.{2}/g) || [], v => parseInt(v, 16));
      return new TextEncoder().encode(value);
    },
    bufToString(value, encoding = 'utf8') {
      const bytes = new Uint8Array(value);
      if (encoding === 'hex') return [...bytes].map(v => v.toString(16).padStart(2, '0')).join('');
      if (encoding === 'base64') { let str = ''; for (const v of bytes) str += String.fromCharCode(v); return btoa(str); }
      return new TextDecoder().decode(bytes);
    },
  };
  self.lx = {
    env: 'mobile', version: '1.9.1', currentScriptInfo: {},
    EVENT_NAMES: { request: 'request', inited: 'inited', updateAlert: 'updateAlert' },
    on(event, callback) { if (event === 'request') handler = callback; },
    send(event, data) {
      if (event === 'inited' && !initialized) { initialized = true; emit({ type: 'init', data }); }
      return Promise.resolve();
    },
    request(url, options, callback) {
      const id = ++sequence;
      if (callbacks.size >= 12) throw new Error('音源并发请求过多');
      callbacks.set(id, callback);
      emit({ type: 'http', id, url, options });
      return () => { callbacks.delete(id); emit({ type: 'cancel', id }); };
    },
    utils: { buffer, crypto: { md5: unsupported, aesEncrypt: unsupported, rsaEncrypt: unsupported,
      randomBytes: size => crypto.getRandomValues(new Uint8Array(size)) } },
  };
  self.onmessage = async ({ data }) => {
    try {
      if (data.type === 'load') {
        self.lx.currentScriptInfo = { name: data.name, rawScript: data.script };
        (0, eval)(data.script);
      } else if (data.type === 'httpResult') {
        const callback = callbacks.get(data.id); callbacks.delete(data.id);
        if (callback) callback(data.error ? new Error(data.error) : null, data.response, data.response?.body);
      } else if (data.type === 'action') {
        if (!handler) throw new Error('音源没有注册请求处理器');
        const result = await handler(data.data);
        emit({ type: 'result', id: data.id, result });
      }
    } catch (error) { emit({ type: 'error', id: data.id, error: String(error.message || error) }); }
  };
}

export class SourceRuntime {
  constructor(http) { this.http = http; this.pending = new Map(); this.requests = new Map(); this.seq = 0; }
  async load(script, name) {
    this.dispose();
    if (script.length > 1024 * 1024) throw new Error('音源脚本超过 1 MiB');
    const frame = this.frame = document.createElement('iframe');
    frame.hidden = true;
    frame.sandbox = 'allow-scripts';
    frame.title = '隔离音源运行时';
    const code = `(${sourceWorker.toString()})()`;
    // No same-origin permission, no network, no external scripts. Only brokered messages.
    const bootstrap = `const w=new Worker(URL.createObjectURL(new Blob([${JSON.stringify(code)}],{type:'text/javascript'})));w.onmessage=e=>parent.postMessage(e.data,'*');w.onerror=()=>parent.postMessage({type:'error',error:'音源脚本执行失败'},'*');onmessage=e=>{if(e.source!==parent)return;if(e.data.type==='stop'){w.terminate();return;}w.postMessage(e.data)};parent.postMessage({type:'ready'},'*');`;
    frame.srcdoc = `<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval' blob:; worker-src blob:; connect-src 'none'"><script>${bootstrap.replace(/<\/script/gi, '<\\/script')}<\/script>`;
    this.listener = event => { if (event.source === frame.contentWindow) this.receive(event.data); };
    window.addEventListener('message', this.listener);
    const ready = this.wait('ready', 8000);
    document.body.append(frame);
    try {
      await ready;
      const init = this.wait('init', 12000);
      this.send({ type: 'load', script, name });
      const data = await init;
      if (!data?.status || !data.sources?.kw?.actions?.includes('musicUrl')) throw new Error('音源未启用酷我播放地址解析');
      this.capabilities = data.sources;
      return data;
    } catch (error) { this.dispose(); throw error; }
  }
  wait(key, ms) {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.pending.delete(key); reject(new Error('音源响应超时，请重新加载音源')); this.dispose(); }, ms);
      this.pending.set(key, { resolve, reject, timer });
    });
  }
  send(data) { this.frame?.contentWindow?.postMessage(data, '*'); }
  settle(key, value, error) {
    const pending = this.pending.get(key); if (!pending) return;
    clearTimeout(pending.timer); this.pending.delete(key);
    if (error) pending.reject(new Error(error)); else pending.resolve(value);
  }
  async receive(message) {
    if (!message || typeof message !== 'object') return;
    if (message.type === 'ready') this.settle('ready');
    else if (message.type === 'init') this.settle('init', message.data);
    else if (message.type === 'result') this.settle(message.id, message.result);
    else if (message.type === 'error') {
      if (message.id) this.settle(message.id, null, message.error);
      else for (const key of this.pending.keys()) this.settle(key, null, message.error);
    } else if (message.type === 'cancel') this.requests.get(message.id)?.abort();
    else if (message.type === 'http') {
      if (this.requests.size >= 12 || this.requests.has(message.id)) return;
      const controller = new AbortController();
      const currentFrame = this.frame;
      this.requests.set(message.id, controller);
      try {
        const response = await this.http(message.url, message.options, controller.signal);
        if (this.frame === currentFrame) this.send({ type: 'httpResult', id: message.id, response });
      } catch (error) {
        if (this.frame === currentFrame) this.send({ type: 'httpResult', id: message.id, error: error.message });
      } finally { if (this.requests.get(message.id) === controller) this.requests.delete(message.id); }
    }
  }
  async musicUrl(track, quality) {
    if (!this.capabilities) throw new Error('请先加载音源');
    const id = ++this.seq;
    const result = this.wait(id, 25000);
    this.send({ type: 'action', id, data: { source: 'kw', action: 'musicUrl', info: { type: quality, musicInfo: track } } });
    const url = await result;
    let parsed; try { parsed = new URL(url); } catch { throw new Error('音源没有返回有效播放地址'); }
    // This specific host was verified to serve the same media path over TLS.
    if (parsed.protocol === 'http:' && parsed.hostname === 'bd-er.kuwo.cn') parsed.protocol = 'https:';
    if (parsed.protocol !== 'https:' || parsed.username || parsed.password) throw new Error('音源返回的地址不是可直接播放的 HTTPS 地址');
    return parsed.href;
  }
  dispose() {
    this.send({ type: 'stop' });
    if (this.listener) window.removeEventListener('message', this.listener);
    this.frame?.remove(); this.frame = null; this.capabilities = null;
    for (const req of this.requests.values()) req.abort(); this.requests.clear();
    for (const key of this.pending.keys()) this.settle(key, null, '音源已重置');
  }
}
