import Foundation

/// Persists image bytes to disk via FileManager and returns the RELATIVE path.
/// Raw bytes must never enter SwiftData — only the relative path is stored.
public final class MediaStore {
    public static let shared = MediaStore()

    private let fileManager = FileManager.default
    private let subdirectory = "Media"

    public init() {}

    /// Absolute base directory: Application Support/SwiftChat/Media.
    public func baseDirectory() throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport
            .appendingPathComponent("SwiftChat", isDirectory: true)
            .appendingPathComponent(subdirectory, isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Write bytes and return the relative path (e.g. "Media/<uuid>.jpg").
    @discardableResult
    public func writeImage(_ data: Data, fileExtension: String = "jpg") throws -> String {
        let base = try baseDirectory()
        let filename = "\(UUID().uuidString).\(fileExtension)"
        let url = base.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return "\(subdirectory)/\(filename)"
    }

    /// Resolve a stored relative path back to an absolute URL for loading.
    public func absoluteURL(forRelativePath relativePath: String) throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("SwiftChat", isDirectory: true)
            .appendingPathComponent(relativePath)
    }

    /// Load bytes off the main thread.
    public func loadImageData(relativePath: String) async throws -> Data {
        let url = try absoluteURL(forRelativePath: relativePath)
        return try Data(contentsOf: url)
    }

    /// Remove an on-disk media file (used when tombstoning a photo message).
    public func removeImage(relativePath: String) {
        guard let url = try? absoluteURL(forRelativePath: relativePath) else { return }
        try? fileManager.removeItem(at: url)
    }
}
