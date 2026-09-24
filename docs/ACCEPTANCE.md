# Picwa 分阶段验收记录

## M1 索引（已验收）

- 原生目录选择器添加多个真实目录，保存 security-scoped bookmarks。
- 后台递归扫描图片扩展名，ImageIO 验证元数据，不加载全部原图。
- SQLite 分批事务、路径去重、无效目录与损坏文件容错。
- 首扫时间优先 EXIF `DateTimeOriginal`、文件创建时间、修改时间，保留 `observedAt`。
- 重启恢复授权与索引，未完成目录续扫。

## M2 时间线与缩略图（已验收）

- `Timeline.swift` 图片时间线与 ImageIO 缩略图，顶部工具栏与扫描提示。
- 日期分组、原比例展示、Today / 7D / 30D / All 切换、密度调节、单击/多选。
- 缩略图最长边 720px，后台串行解码，64 MB / 240 张内存缓存。

## M3–M5（已实现，验收部分保留）

- FSEvents 实时同步：新增、删除、重命名后时间墙更新；删除同步已真实验证。
- 生成时间展示：优先 EXIF `DateTimeOriginal`，回退文件创建时间，不再误显示扫描时间。
- 多选拖动复制到其他文件夹，一次复制所选全部图片。
- 快速滚动时间提示残留、默认展示时间等交互问题已修复。
- 时间年轮：中心轴线 + 脊柱 + 刻度尺视觉，密度滑块、右键菜单、全选/删除、搜索与日期范围。

## 上架前状态（历史记录：2026-09-08）

- 当时产品包名、可执行文件名与显示名使用此前品牌；本机旧沙盒数据仍保留。2026-09-25 切换至 Picwa 后使用新的 Bundle ID `cc.leowy.picwa`，新旧容器彼此独立。
- 功能侧基本就绪，本地 `zsh scripts/bundle.sh` 构建可用。
- 已加入 Info.plist、`scripts/archive.sh`、`scripts/check-release-readiness.sh`，可通过 Xcode 生成无签名通用 Archive 与 dSYM，并检查包结构、隐私清单和图标。
- 已加入 App 内隐私政策页面及 `docs/PRIVACY_POLICY.md`、`docs/APP_STORE_METADATA.md`、`docs/STORE_ASSETS.md`、`docs/RELEASE_CHECKLIST.md`。
- 运营者名称已固定为中文“行与未见”、英文“Leowy”；当时隐私政策发布在旧品牌站点。
- 全球推广的最小双语版本已完成：英文为网站默认语言，中文使用 `/zh/` 路径；隐私政策、支持页和 App 内在线链接均按系统语言对应到中英文页面。
- 发布侧仍待完成：Apple Distribution 签名、App Store Connect 记录、商店截图、隐私问卷与上传通道。
- 隐私清单已加入 `PrivacyInfo.xcprivacy`，申报文件时间戳 API（3B52.1，用户授予访问的目录）和 UserDefaults（CA92.1，本应用自身设置）。
- 尚未最终验收：正式签名后的真实安装/启动、App Store Connect 上传验证，以及大目录性能基线。

## 品牌重命名（2026-09-25）

- 对外品牌、SwiftPM 套件、可执行文件、应用包、沙盒 Bundle ID 与线上站点统一为 Picwa。
- 新 Bundle ID 为 `cc.leowy.picwa`；旧开发容器保留在本机，不会被清理。新身份首次启动将创建独立容器，文件夹需要重新授权。
- GitHub 仓库已更名为 `leowyleo/picwa` 并推送 Picwa 品牌提交；Cloudflare Pages 项目已改名并连接 `picwa.leowy.cc`。
- 新品牌域名的首页、中英文隐私政策和支持页均实测 HTTP 200；旧网站主机名通过 Cloudflare 301 保留路径和查询参数后跳转至新域名。
