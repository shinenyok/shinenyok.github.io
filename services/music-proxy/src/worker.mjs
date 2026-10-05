// Metadata-only proof of concept. Never execute source scripts in this Worker.
const MAX_BODY = 64 * 1024;
const MAX_RESPONSE = 2 * 1024 * 1024;
const METHODS = ['GET', 'HEAD', 'POST'];
const REQUEST_HEADERS = new Set(['accept', 'content-type', 'user-agent', 'referer', 'origin', 'x-request-key']);
const list = value => (value || '').split(',').map(v => v.trim()).filter(Boolean);
class ProxyError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

async function readLimited(stream, limit) {
  if (!stream) return new Uint8Array();
  const reader = stream.getReader();
  const chunks = [];
  let size = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) {
        await reader.cancel();
        throw new ProxyError(413, 'Payload exceeds proxy limit');
      }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const result = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { result.set(chunk, offset); offset += chunk.byteLength; }
  return result;
}

export function createWorker(upstreamFetch = fetch) {
  return {
    async fetch(request, env) {
      const url = new URL(request.url);
      const origin = request.headers.get('origin');
      const allowed = list(env.ALLOWED_ORIGINS).includes(origin);
      const cors = {
        'Cache-Control': 'no-store',
        'Vary': 'Origin',
        ...(allowed ? {
          'Access-Control-Allow-Origin': origin,
          'Access-Control-Allow-Methods': METHODS.join(', '),
          'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-LX-Proxy-Headers',
          'Access-Control-Expose-Headers': 'X-LX-Upstream-URL',
        } : {}),
      };
      const json = (status, data) => Response.json(data, { status, headers: cors });
      if (url.pathname === '/health' && request.method === 'GET') {
        return json(200, { ok: true, configured: Boolean(env.PROXY_TOKEN), mode: 'metadata-only' });
      }
      if (url.pathname !== '/__lx_proxy') return json(404, { error: 'Not found' });
      if (origin && !allowed) return json(403, { error: 'Origin not allowed' });
      if (request.method === 'OPTIONS') {
        if (!allowed || !METHODS.includes(request.headers.get('access-control-request-method'))) {
          return json(403, { error: 'Preflight rejected' });
        }
        return new Response(null, { status: 204, headers: cors });
      }
      // CORS is not authentication. Fail closed until a secret is configured.
      if (!env.PROXY_TOKEN) return json(503, { error: 'Proxy token not configured' });
      if (request.headers.get('authorization') !== `Bearer ${env.PROXY_TOKEN}`) {
        return json(401, { error: 'Authentication required' });
      }
      if (!METHODS.includes(request.method)) return json(405, { error: 'Method not allowed' });
      let timer;
      try {
        let target;
        try { target = new URL(url.searchParams.get('url')); }
        catch { throw new ProxyError(400, 'Invalid target URL'); }
        if (!['https:', 'http:'].includes(target.protocol) || target.username || target.password ||
            target.port || !list(env.ALLOWED_HOSTS).includes(target.hostname)) {
          throw new ProxyError(403, 'Target not allowed');
        }
        const headers = new Headers({ Accept: 'application/json', 'User-Agent': 'Mozilla/5.0' });
        const contentType = request.headers.get('content-type');
        if (contentType) headers.set('content-type', contentType);
        const rawHeaders = request.headers.get('x-lx-proxy-headers');
        if (rawHeaders) {
          let extra;
          try { extra = JSON.parse(rawHeaders); } catch { throw new ProxyError(400, 'Invalid forwarded headers'); }
          if (!extra || typeof extra !== 'object' || Array.isArray(extra)) throw new ProxyError(400, 'Invalid forwarded headers');
          for (const [key, value] of Object.entries(extra)) {
            if (!REQUEST_HEADERS.has(key.toLowerCase()) || typeof value !== 'string') {
              throw new ProxyError(400, 'Forwarded header not allowed');
            }
            try { headers.set(key, value); } catch { throw new ProxyError(400, 'Invalid forwarded header value'); }
          }
        }
        const controller = new AbortController();
        const configuredTimeout = Number(env.UPSTREAM_TIMEOUT_MS) || 13000;
        timer = setTimeout(() => controller.abort(), Math.min(20000, Math.max(1, configuredTimeout)));
        const body = request.method === 'POST' ? await readLimited(request.body, MAX_BODY) : undefined;
        const response = await upstreamFetch(target.href, {
          method: request.method, headers, body, signal: controller.signal, redirect: 'manual',
        });
        // Do not follow redirects to an unchecked host, or leak authorization.
        if (response.status >= 300 && response.status < 400) {
          await response.body?.cancel();
          throw new ProxyError(502, 'Upstream redirect requires explicit review');
        }
        const type = response.headers.get('content-type') || 'application/octet-stream';
        if (/^(audio|video)\//i.test(type)) {
          await response.body?.cancel();
          throw new ProxyError(415, 'Audio/video forwarding is disabled in this trial');
        }
        const bytes = await readLimited(response.body, MAX_RESPONSE);
        return new Response(request.method === 'HEAD' || [204, 205, 304].includes(response.status) ? null : bytes, {
          status: response.status,
          headers: { ...cors, 'Content-Type': type, 'X-Content-Type-Options': 'nosniff',
            'Content-Security-Policy': "default-src 'none'; sandbox", 'X-LX-Upstream-URL': target.href },
        });
      } catch (error) {
        const status = error instanceof ProxyError ? error.status : error.name === 'AbortError' ? 504 : 502;
        return json(status, { error: error instanceof ProxyError ? error.message : status === 504 ? 'Upstream timed out' : 'Upstream request failed' });
      } finally { clearTimeout(timer); }
    },
  };
}
export default createWorker();
