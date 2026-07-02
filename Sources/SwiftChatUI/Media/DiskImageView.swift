import SwiftUI
import SwiftChatKit

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

/// Asynchronously loads an image from disk (by its stored relative path).
/// Raw bytes live on the file system, never in SwiftData.
public struct DiskImageView: View {
    public let relativePath: String
    @State private var image: Image?
    @State private var failed = false

    public init(relativePath: String) {
        self.relativePath = relativePath
    }

    public var body: some View {
        Group {
            if let image {
                image.resizable().scaledToFit()
            } else if failed {
                Image(systemName: "photo").foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .task(id: relativePath) { await load() }
    }

    private func load() async {
        do {
            let data = try await MediaStore.shared.loadImageData(relativePath: relativePath)
            if let platform = PlatformImage(data: data) {
                #if canImport(UIKit)
                image = Image(uiImage: platform)
                #else
                image = Image(nsImage: platform)
                #endif
            } else {
                failed = true
            }
        } catch {
            failed = true
        }
    }
}
