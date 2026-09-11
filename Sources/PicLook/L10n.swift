import Foundation

enum L {
    static var isChinese: Bool {
        Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
    }

    static func tr(_ zh: String, _ en: String) -> String {
        isChinese ? zh : en
    }

    static func imageCount(_ count: Int) -> String {
        isChinese ? "\(count) 张图片" : (count == 1 ? "1 image" : "\(count) images")
    }

    static func selectedCount(_ count: Int) -> String {
        isChinese ? "已选 \(count) 张图片" : (count == 1 ? "1 image selected" : "\(count) images selected")
    }
}
