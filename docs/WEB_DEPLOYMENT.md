# Picrow 公网页部署

生产部署使用 GitHub + Cloudflare Pages，网站不依赖这台 Mac：

- GitHub 仓库：`https://github.com/leowyleo/picrow`
- Cloudflare Pages 输出目录：`docs/site`
- 公网入口：`https://picrow.leowy.cc/`
- 英文首页：`https://picrow.leowy.cc/`
- 中文首页：`https://picrow.leowy.cc/zh/`
- 英文隐私政策：`https://picrow.leowy.cc/privacy`
- 中文隐私政策：`https://picrow.leowy.cc/zh/privacy`
- 英文支持页：`https://picrow.leowy.cc/support`
- 中文支持页：`https://picrow.leowy.cc/zh/support`

`docs/site/_redirects` 保留 `/privacy`、`/support`、`/zh/privacy`、`/zh/support` 这四个 Apple 可直接访问的稳定路径。隐私政策和支持页均应返回 HTTP 200，并显示运营者“行与未见 / Leowy”。支持页提供常见使用说明，并公开支持邮箱 `leowy.lwy@gmail.com` 与 GitHub Issues。

本地服务 `127.0.0.1:3020` 与 Cloudflare Tunnel 路由仅保留作开发或回滚，不作为生产依赖。
