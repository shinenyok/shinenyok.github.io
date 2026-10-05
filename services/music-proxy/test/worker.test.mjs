import test from 'node:test';
import assert from 'node:assert/strict';
import { createWorker } from '../src/worker.mjs';

const env = { PROXY_TOKEN: 'test-only', ALLOWED_ORIGINS: 'https://www.shineyoki.top', ALLOWED_HOSTS: 'search.kuwo.cn' };
const request = (target = 'http://search.kuwo.cn/r.s', options = {}) => new Request(
  `https://proxy.example/__lx_proxy?url=${encodeURIComponent(target)}`,
  { ...options, headers: { authorization: 'Bearer test-only', origin: 'https://www.shineyoki.top', ...options.headers } },
);

test('authenticated POST preserves body and selected headers, never forwards proxy credentials', async () => {
  let seen;
  const worker = createWorker(async (url, options) => {
    seen = { url, ...options };
    return Response.json({ ok: true }, { headers: { 'set-cookie': 'private=1' } });
  });
  const response = await worker.fetch(request(undefined, { method: 'POST', body: 'a=1', headers: {
    'content-type': 'application/x-www-form-urlencoded', 'x-lx-proxy-headers': JSON.stringify({ 'User-Agent': 'LX-test' }),
  } }), env);
  assert.equal(response.status, 200);
  assert.equal(new TextDecoder().decode(seen.body), 'a=1');
  assert.equal(seen.headers.get('user-agent'), 'LX-test');
  assert.equal(seen.headers.get('authorization'), null);
  assert.equal(response.headers.get('set-cookie'), null);
  assert.equal(response.headers.get('access-control-allow-origin'), 'https://www.shineyoki.top');
  assert.equal(seen.redirect, 'manual');
});

test('rejects unauthenticated, unknown origins, nonallowlisted targets and forged forwarded headers before fetch', async () => {
  const worker = createWorker(() => { assert.fail('Must not contact upstream'); });
  for (const [req, config, expected] of [
    [request(undefined, { headers: { authorization: '' } }), env, 401],
    [request(), { ...env, PROXY_TOKEN: '' }, 503],
    [request(undefined, { headers: { origin: 'https://other.example' } }), env, 403],
    ...['http://127.0.0.1/', 'http://169.254.169.254/', 'https://search.kuwo.cn.evil.example/',
      'http://search.kuwo.cn:8080/', 'http://user:password@search.kuwo.cn/', 'file:///etc/passwd'].map(url => [request(url), env, 403]),
    [request('invalid'), env, 400],
    [request(undefined, { headers: { 'x-lx-proxy-headers': '{' } }), env, 400],
    [request(undefined, { headers: { 'x-lx-proxy-headers': '{"Host":"localhost"}' } }), env, 400],
    [request(undefined, { method: 'DELETE' }), env, 405],
    [request(undefined, { method: 'POST', body: 'x'.repeat(65537) }), env, 413],
  ]) assert.equal((await worker.fetch(req, config)).status, expected);
});

test('preflight works without exposing the secret; wrong method rejected', async () => {
  const worker = createWorker();
  assert.equal((await worker.fetch(request(undefined, { method: 'OPTIONS', headers: {
    authorization: '', 'access-control-request-method': 'POST',
  } }), env)).status, 204);
  assert.equal((await worker.fetch(request(undefined, { method: 'OPTIONS', headers: {
    'access-control-request-method': 'DELETE',
  } }), env)).status, 403);
});

test('redirects, oversized responses and audio are rejected', async () => {
  for (const [upstream, expected] of [
    [new Response(null, { status: 302, headers: { location: 'http://127.0.0.1/' } }), 502],
    [new Response('audio', { headers: { 'content-type': 'audio/mpeg' } }), 415],
    [new Response(new Uint8Array(2 * 1024 * 1024 + 1)), 413],
  ]) assert.equal((await createWorker(async () => upstream).fetch(request(), env)).status, expected);
});

test('upstream errors and timeouts produce bounded responses', async () => {
  assert.equal((await createWorker(async () => { throw new Error('private detail'); }).fetch(request(), env)).status, 502);
  const worker = createWorker((_url, { signal }) => new Promise((resolve, reject) => {
    signal.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')), { once: true });
  }));
  assert.equal((await worker.fetch(request(), { ...env, UPSTREAM_TIMEOUT_MS: '5' })).status, 504);
});

test('HEAD/204 responses have no body and preserve status', async () => {
  const response = await createWorker(async () => new Response(null, { status: 204 })).fetch(request(), env);
  assert.equal(response.status, 204);
  assert.equal(await response.text(), '');
});

test('additional tokens work alongside original; malformed lists never open access', async () => {
  const worker = createWorker(async () => Response.json({ ok: true }));
  const multi = { ...env, PROXY_TOKENS: JSON.stringify(['extra-one', 'extra-two']) };
  for (const token of ['test-only', 'extra-one', 'extra-two']) {
    assert.equal((await worker.fetch(request(undefined, { headers: { authorization: `Bearer ${token}` } }), multi)).status, 200);
  }
  assert.equal((await worker.fetch(request(undefined, { headers: { authorization: 'Bearer wrong' } }), multi)).status, 401);
  for (const value of ['invalid', '{}', '[null, "", 123]']) {
    const config = { ...env, PROXY_TOKEN: '', PROXY_TOKENS: value };
    assert.equal((await worker.fetch(request(), config)).status, 503);
  }
  const onlyExtra = { ...multi, PROXY_TOKEN: '' };
  assert.equal((await worker.fetch(request(undefined, { headers: { authorization: 'Bearer extra-one' } }), onlyExtra)).status, 200);
});

test('session authenticates without contacting music upstream and supports CORS',async()=>{
 const worker=createWorker(()=>assert.fail('Session must not fetch upstream'));
 const req=(method='GET',token='test-only')=>new Request('https://proxy.example/session',{method,headers:{origin:'https://www.shineyoki.top',authorization:`Bearer ${token}`,'access-control-request-method':'GET'}});
 const response=await worker.fetch(req(),env);
 assert.equal(response.status,200);assert.deepEqual(await response.json(),{ok:true});
 assert.equal(response.headers.get('access-control-allow-origin'),'https://www.shineyoki.top');
 assert.equal((await worker.fetch(req('GET','wrong'),env)).status,401);
 assert.equal((await worker.fetch(req('OPTIONS',''),env)).status,204);
 assert.equal((await worker.fetch(req('POST'),env)).status,405);
});
