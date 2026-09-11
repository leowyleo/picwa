// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Picrow", platforms: [.macOS(.v13)], products: [.executable(name: "Picrow", targets: ["PicLook"])], targets: [.systemLibrary(name: "CSQLite"), .executableTarget(name: "PicLook", dependencies: ["CSQLite"])])
