import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L.tr("隐私政策", "Privacy Policy"))
                    .font(.title2.weight(.semibold))
                Spacer()
                Button(L.tr("完成", "Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Divider()
                .padding(.vertical, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(L.tr("最后更新：2026 年 9 月 8 日", "Last updated: September 8, 2026"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text(L.tr("运营者：行与未见", "Operator: Leowy"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        let privacyURL = L.isChinese
                            ? "https://picrow.leowy.cc/zh/privacy"
                            : "https://picrow.leowy.cc/privacy"
                        if let url = URL(string: privacyURL) {
                            Link(L.tr("在线版本", "Online version"), destination: url)
                                .font(.caption)
                        }
                    }

                    policySection(
                        title: L.tr("我们处理什么信息", "What Picrow processes"),
                        body: L.tr(
                            "Picrow 只处理你主动选择的文件夹中的图片文件。为了建立时间线，应用会在本机读取图片的文件名、路径、尺寸和创建时间等元数据，并在本机保存索引。",
                            "Picrow processes images only in folders you choose. To build the timeline, it reads image metadata such as file names, paths, dimensions, and creation dates, and stores the index locally."
                        )
                    )

                    policySection(
                        title: L.tr("我们不会做什么", "What Picrow does not do"),
                        body: L.tr(
                            "Picrow 不上传图片或索引，不使用广告、不进行跨应用跟踪，也不接入第三方分析服务。原始图片始终留在你的 Mac 上。",
                            "Picrow does not upload images or indexes, serve ads, track you across apps, or use third-party analytics. Your original images stay on your Mac."
                        )
                    )

                    policySection(
                        title: L.tr("文件操作", "File operations"),
                        body: L.tr(
                            "扫描只发生在你授权的文件夹内。复制和删除操作只会在你明确执行后发生；Picrow 不会自动删除文件。",
                            "Scanning is limited to folders you authorize. Copy and delete actions happen only after you explicitly perform them; Picrow never deletes files automatically."
                        )
                    )

                    policySection(
                        title: L.tr("本地数据", "Local data"),
                        body: L.tr(
                            "文件夹授权、扫描设置和图片索引保存在 Picrow 的沙盒容器中，仅供本机 Picrow 使用。你可以在设置中移除已添加的文件夹。",
                            "Folder permissions, scan settings, and the image index are stored in Picrow’s sandbox container for use by Picrow on this Mac. You can remove added folders in Settings."
                        )
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .frame(width: 560, height: 500)
    }

    private func policySection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
