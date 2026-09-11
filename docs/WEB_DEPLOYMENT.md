# Picrow 公网页部署

当前部署沿用 Arche 的 Cloudflare Tunnel：

- 本地静态服务：`127.0.0.1:3020`
- 公网入口：`https://picrow.leowy.cc/`
- 英文首页：`https://picrow.leowy.cc/`
- 中文首页：`https://picrow.leowy.cc/zh/`
- 英文隐私政策：`https://picrow.leowy.cc/privacy`
- 中文隐私政策：`https://picrow.leowy.cc/zh/privacy`
- 英文支持页：`https://picrow.leowy.cc/support`
- 中文支持页：`https://picrow.leowy.cc/zh/support`

服务由 `~/Library/LaunchAgents/cc.leowy.picrow-site.plist` 保持运行，Tunnel 路由位于：

`~/Library/Application Support/ArcheQuant/cloudflared.yml`

隐私政策和支持页均应返回 HTTP 200，并显示运营者“行与未见 / Leowy”。支持页提供常见使用说明，并公开支持邮箱 `leowy.lwy@gmail.com` 与 GitHub Issues。
