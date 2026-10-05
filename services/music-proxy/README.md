# 音乐代理验证版

代理用于搜索和音源解析的小请求，音频由浏览器直接访问 HTTPS 地址。
网站已加入 `web/music` 隐藏音乐面板；原 music 项目未改动。无需数据库、存储桶或付费方案。

## 当前部署状态（2026-10-02）

- 已通过 Wrangler OAuth 授权，部署 `cotool-music-proxy` 并设置 `PROXY_TOKEN` secret。
- 地址：https://cotool-music-proxy.cotool-music-proxy.workers.dev
- 健康检查：https://cotool-music-proxy.cotool-music-proxy.workers.dev/health
- 本地口令存于被 Git 忽略的 `.dev.vars`，文件权限为 0600，不要提交或粘贴到聊天中。
- 用户浏览器健康检查成功：`ok: true`、`configured: true`。
- 浏览器端真实云端搜索验证成功：本机 `http://127.0.0.1:8080` 页面携带 Bearer 口令，经 CORS 预检访问 Worker，返回 HTTP 200、3 条“晴天”结果（含 `MUSIC_228908`）。验证覆盖浏览器 → Worker → 酷我搜索接口。
- 本机 Node fetch/curl 仍连接失败，终端域名解析结果异常；浏览器链路正常。
- 2026-10-05：参考音源在隔离 Worker 中初始化成功；通过云端代理解析“晴天”，浏览器音频实际播放超过 49 秒（总长 269.75 秒，无媒体错误）。
- 已验证 `bd-er.kuwo.cn` 同一音频路径支持 HTTPS，将该域名的 HTTP 播放地址升级为 HTTPS；其他 HTTP 播放地址仍拒绝。

## 本地验证

需要 Node.js 22 或更新版本。在本目录运行：

```sh
npm ci
npm test
```

不启动服务也可测试本机处理器与真实搜索接口：`npm run probe -- --local`。
2026-10-02 本机验证获得 3 条“晴天”结果；这不是 Cloudflare 云端验证。

新建 `.dev.vars`（已忽略，不提交）：

```text
PROXY_TOKEN=自行生成的随机长口令
```

运行 `npm run dev`。`/health` 返回 `configured: true` 表示设置了口令。
在另一个终端用相同口令测试搜索，口令只放本地环境变量，不写进网页或 Git：

```sh
read -s PROXY_TOKEN
export PROXY_TOKEN
npm run probe -- http://localhost:8787
unset PROXY_TOKEN
```

## Cloudflare 免费方案部署

1. 本人注册并验证邮箱：https://dash.cloudflare.com/sign-up
2. 本目录执行 `npx wrangler login`，在浏览器完成授权。
3. 执行 `npm run deploy`，如果首次使用 Workers，按提示创建 workers.dev 子域。
4. 执行 `npx wrangler secret put PROXY_TOKEN`，交互输入随机长口令。未设置口令时代理拒绝请求。
5. 用部署输出的真实地址运行 `npm run probe -- https://实际地址.workers.dev`，口令按本地验证步骤输入。

不需要迁移现有域名或 DNS。不启用付费计划。可以执行 `npx wrangler delete` 删除这个试验 Worker。

## 边界与后续

- 接口兼容现有代理的路径 `/__lx_proxy?url=...` 和 `X-LX-Proxy-Headers`，新增 `Authorization: Bearer ...`。
- `ALLOWED_HOSTS` 只包含已检查的两个搜索域名和 `lxmusicapi.onrender.com`，精确匹配；新增音源需检查域名后修改配置。不跟随重定向。
- CORS 限制网站来源，口令单独鉴权。隐藏入口本身不是权限控制。未来网页可由本人临时输入口令，不能在静态资源内硬编码。
- 请求体最多 64 KiB，响应最多 2 MiB，上游超时默认 13 秒。禁用音视频转发。
- 已实现最小 LX 浏览器运行时：初始化、request 事件、HTTP 回调、取消、基础 buffer。加密、二进制、multipart、其他音乐平台暂未适配；不会假装兼容所有音源。
- 搜索成功仅证明该接口可达。还需要云端验证音源脚本依赖、IP 绑定、浏览器直连音频和实际播放。
- 单元测试使用模拟上游；真实连通性需运行 probe，不能以单元测试通过替代云端实测。

## 网站使用

1. 点击右下角浅灰色 ♪，首次点击才加载面板。
2. 输入访问口令，或选择本目录的 `.dev.vars`（macOS 文件选择器可按 Command+Shift+. 显示隐藏文件）。点击“连接服务”。口令只保留在页面内存中，不写入静态资源。
3. 点击“加载 music 参考音源”，直接从原目录对应的 GitHub 内容 API 读取 Huibq 脚本，或导入本地 `.js`。第三方脚本未捆绑到网站仓库中。
4. 搜索歌曲，点击结果播放。收起面板保留 iframe 和音频，刷新后需要重新连接、加载音源。

音源执行于无同源权限的 sandbox iframe 内的独立 Worker；CSP 禁止直接联网，HTTP 经父页面白名单和云端鉴权转发。脚本拿不到代理口令。初始化/解析超时会销毁运行时。

验证命令：`npm test`（代理和 LX 协议测试）、仓库根目录 `flutter build web --release --no-pub --pwa-strategy=none`。
浏览器真实播放成功仅覆盖上述参考音源和曲目，不保证其他音源、曲目或网络环境均可用。
