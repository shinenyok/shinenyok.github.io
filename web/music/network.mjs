// Avoid AbortSignal.any/timeout: older mobile browsers do not implement them.
export async function requestText(url, options = {}, timeoutMs = 20000, fetcher = fetch) {
  const controller = new AbortController();
  const signal = options.signal;
  let timedOut = false;
  const cancel = () => controller.abort();
  if (signal?.aborted) cancel();
  else signal?.addEventListener('abort', cancel, { once: true });
  const timer = setTimeout(() => { timedOut = true; cancel(); }, timeoutMs);
  try {
    const response = await fetcher(url, { ...options, signal: controller.signal });
    const text = await response.text();
    return { response, text };
  } catch (error) {
    if (timedOut) throw new Error('连接超时：请检查手机网络是否能打开服务检测页面');
    if (controller.signal.aborted) throw new Error('请求已取消');
    if (error instanceof TypeError) throw new Error(`浏览器无法连接音乐服务（当前网页：${location.origin}）。请先打开下方“服务检测页面”：若也打不开，通常是当前网络拦截了 Cloudflare 域名；若检测页显示 JSON，再检查网站地址与跨域设置。`);
    throw error;
  } finally {
    clearTimeout(timer);
    signal?.removeEventListener('abort', cancel);
  }
}

export function normalizeToken(input) {
  const raw = String(input).trim().replace(/^PROXY_TOKEN\s*=\s*/, '').replace(/^Bearer\s+/i, '').trim();
  // Issued keys are hex; whitespace can be inserted when copying on a phone.
  return raw.replace(/\s/g, '');
}

export function responseError(status, detail) {
  if (status === 401) return '口令不正确或已失效，请重新复制完整 token';
  if (status === 403) return '当前网站地址或音源未获允许，请从 https://www.shineyoki.top 打开';
  if (status === 503) return '服务暂未配置完成，请稍后再试';
  return `请求失败（${status}）：${detail || '服务暂时不可用'}`;
}
