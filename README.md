# Picwa

本地优先的 macOS 图片时间线工具。按图片真实生成时间分组，以时间年轮方式浏览本地图片，支持按日期范围、密度与多选操作。

## 运行

```sh
zsh scripts/bundle.sh
open dist/Picwa.app
```

需要本机 Xcode。脚本仅为开发构建指定 `DEVELOPER_DIR`，不更改系统设置。App 使用本地临时签名与沙盒，只申请用户所选目录的读写访问，并通过 security-scoped bookmark 持久化授权。

## 发布准备命令

```sh
# 检查当前 App 包的本地发布准备状态
zsh scripts/check-release-readiness.sh

# 用 Xcode 生成无签名通用 Archive 和 dSYM
zsh scripts/archive.sh /tmp/Picwa.xcarchive
```

`archive.sh` 只生成本地检查用的无签名归档，不会访问 Apple 账号，也不会上传。正式签名、App Store Connect 和审核步骤见 `docs/RELEASE_CHECKLIST.md`。

## 已实现

- 目录选择与授权恢复，未完成目录断点续扫。
- 后台递归扫描 jpg/jpeg/png/webp/gif/heic/tiff/bmp，ImageIO 验证元数据与真实缩略图。
- SQLite 分批事务、路径去重、无效目录与损坏文件容错。
- 按图片生成时间（优先 EXIF `DateTimeOriginal`，回退文件创建时间）倒序的时间年轮。
- Today / 7D / 30D / All 快捷范围、⌘= / ⌘- 密度调节。
- 多选、拖动复制到其他文件夹、删除与删除后的实时同步。
- 系统主题跟随、键盘可达与基础无障碍标签。

## 上架状态

本地功能与发布准备已完成基础版：包含沙盒权限、隐私清单、正式图标、App 内隐私政策、商店元数据/截图草案，以及基于 Xcode 的无签名 Archive 脚本。

当前仍不能直接提交：尚未有 Apple Distribution 签名、App Store Connect App Record、公开隐私政策 URL、支持 URL、商店截图和账号侧上传验证。`scripts/archive.sh` 会生成包含通用二进制和 dSYM 的无签名 Xcode Archive；账号相关步骤见 `docs/RELEASE_CHECKLIST.md`。

## 文件

- `Sources/Picwa/Timeline.swift`：时间线分组、按需缩略图与 64 MB 内存缓存。
- `Sources/Picwa/Index.swift`：ImageIO 元数据扫描、SQLite 分批事务、路径去重。
- `Sources/Picwa/PicwaApp.swift`：原生界面、目录授权、FSEvents 实时同步与重启恢复。
- `scripts/bundle.sh`、`scripts/Picwa.entitlements`、`PrivacyInfo.xcprivacy`：本地沙盒 App 打包与隐私清单。
- `scripts/VerifyIndex.swift`：真实文件扫描、重复扫描、持久化与无效目录验证入口。
- `docs/ACCEPTANCE.md`：分阶段验收记录。

## 数据位置

`~/Library/Containers/cc.leowy.picwa/Data/Library/Application Support/Picwa/`
