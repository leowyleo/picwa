// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Picwa", platforms: [.macOS(.v13)], products: [.executable(name: "Picwa", targets: ["Picwa"])], targets: [.systemLibrary(name: "CSQLite"), .executableTarget(name: "Picwa", dependencies: ["CSQLite"])])
