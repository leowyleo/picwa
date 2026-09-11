import Foundation
@main struct VerifyIndex {
    static func main() async throws {
        let args = CommandLine.arguments
        let data = URL(fileURLWithPath: args[1])
        let db = URL(fileURLWithPath: args[2])
        let index = ImageIndex(url: db)
        let result = try await index.scan(data) { _ in }
        let first = try await index.snapshot()
        _ = try await index.scan(data) { _ in }
        let duplicate = try await index.snapshot()
        guard first.count == duplicate.count else { fatalError("Duplicate records") }
        let reopened = ImageIndex(url: db)
        let saved = try await reopened.snapshot()
        guard saved.count == first.count else { fatalError("Persistence failure") }
        do { _ = try await index.scan(data.appendingPathComponent("missing-folder")) { _ in }; fatalError("Missing folder accepted") }
        catch is IndexFailure {}
        print("indexed=\(result.indexed) skipped=\(result.skipped) errors=\(result.errors) persisted=\(saved.count) duplicateScan=OK missingFolder=handled")
    }
}
