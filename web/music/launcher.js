// Small launcher only; the player is loaded on first use.
const trigger = document.createElement('button');
trigger.type = 'button';
trigger.textContent = '♪';
trigger.title = '听一会儿';
trigger.setAttribute('aria-label', '打开音乐面板');
trigger.setAttribute('aria-expanded', 'false');
trigger.style.cssText = 'position:fixed;right:14px;bottom:5px;z-index:10000;width:28px;height:26px;border:0;background:transparent;color:#84918a;font:18px serif;cursor:pointer;border-radius:6px';
let panel;
function toggle(show) {
  if (!panel) {
    panel = document.createElement('iframe');
    panel.src = new URL('index.html', import.meta.url).href;
    panel.title = '听一会儿 · 音乐';
    panel.allow = 'autoplay';
    panel.style.cssText = 'position:fixed;right:12px;bottom:40px;z-index:9999;width:min(400px,calc(100vw - 24px));height:min(650px,calc(100dvh - 62px));border:1px solid #dce3dc;border-radius:18px;box-shadow:0 12px 50px #22372a26;background:#f8faf6';
    document.body.append(panel);
  }
  panel.hidden = !show;
  trigger.setAttribute('aria-expanded', String(show));
  trigger.setAttribute('aria-label', show ? '收起音乐面板' : '打开音乐面板');
  if (!show) trigger.focus();
}
trigger.onclick = () => toggle(!panel || panel.hidden);
window.addEventListener('message', event => {
  if (panel && event.source === panel.contentWindow && event.origin === location.origin && event.data === 'music:close') toggle(false);
});
document.addEventListener('keydown', event => { if (event.key === 'Escape' && panel && !panel.hidden) toggle(false); });
document.body.append(trigger);
