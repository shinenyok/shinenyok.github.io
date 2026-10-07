import { createServer } from 'node:http';
import { createWorker } from './worker.mjs';

const port = Number(process.env.PORT) || 10000;
const allowedOrigins = process.env.ALLOWED_ORIGINS || 'https://www.shineyoki.top,https://shineyoki.top';
const allowedHosts = process.env.ALLOWED_HOSTS || 'search.kuwo.cn,songsearch.kugou.com,lxmusicapi.onrender.com';
const env = {
  ALLOWED_ORIGINS: allowedOrigins,
  ALLOWED_HOSTS: allowedHosts,
  PROXY_TOKEN: process.env.PROXY_TOKEN || '',
  PROXY_TOKENS: process.env.PROXY_TOKENS || '[]',
  UPSTREAM_TIMEOUT_MS: process.env.UPSTREAM_TIMEOUT_MS || '13000',
};
const worker = createWorker();
const maxBodyBytes = 64 * 1024;

const server = createServer(async (incoming, outgoing) => {
  try {
    const chunks = [];
    let size = 0;
    let tooLarge = false;
    for await (const chunk of incoming) {
      size += chunk.byteLength;
      if (size > maxBodyBytes) tooLarge = true;
      else if (!tooLarge) chunks.push(chunk);
    }
    if (tooLarge) {
      outgoing.writeHead(413, { 'content-type': 'application/json; charset=utf-8' });
      outgoing.end(JSON.stringify({ error: 'Payload exceeds proxy limit' }));
      return;
    }
    const body = chunks.length ? Buffer.concat(chunks) : undefined;
    const request = new Request(new URL(incoming.url || '/', `http://${incoming.headers.host || 'localhost'}`), {
      method: incoming.method,
      headers: incoming.headers,
      body: ['GET', 'HEAD'].includes(incoming.method || '') ? undefined : body,
    });
    const response = await worker.fetch(request, env);
    outgoing.writeHead(response.status, Object.fromEntries(response.headers));
    outgoing.end(incoming.method === 'HEAD' ? undefined : Buffer.from(await response.arrayBuffer()));
  } catch (error) {
    console.error('Request handling failed:', error);
    if (!outgoing.headersSent) outgoing.writeHead(500, { 'content-type': 'application/json; charset=utf-8' });
    outgoing.end(JSON.stringify({ error: 'Internal server error' }));
  }
});

server.listen(port, '0.0.0.0', () => console.log(`Music proxy listening on ${port}`));
