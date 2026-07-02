import SwiftUI
import LinkPresentation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Inline YouTube (or any) link preview using LinkPresentation's LPMetadataProvider.
/// This is the one permitted public-internet fetch — no API key required.
public struct LinkPreviewView: View {
    public let urlString: String

    @State private var title: String?
    @State private var thumbnail: Image?
    @State private var isLoading = true

    public init(urlString: String) {
        self.urlString = urlString
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let thumbnail {
                thumbnail
                    .resizable()
                    .scaledToFill()
                    .frame(height: 140)
                    .clipped()
            } else if isLoading {
                ProgressView().frame(height: 140).frame(maxWidth: .infinity)
            }
            Text(title ?? urlString)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .background(Color.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: urlString) { await fetchMetadata() }
    }

    private func fetchMetadata() async {
        guard let url = URL(string: urlString) else { isLoading = false; return }
        let provider = LPMetadataProvider()
        do {
            let metadata = try await provider.startFetchingMetadata(for: url)
            if let t = metadata.title { self.title = t }
            if let imageProvider = metadata.imageProvider {
                if let img = await loadImage(from: imageProvider) {
                    self.thumbnail = img
                }
            }
        } catch {
            // Leave title fallback in place.
        }
        isLoading = false
    }

    private func loadImage(from provider: NSItemProvider) async -> Image? {
        await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: PlatformImage.self) { object, _ in
                #if canImport(UIKit)
                if let ui = object as? UIImage {
                    continuation.resume(returning: Image(uiImage: ui)); return
                }
                #elseif canImport(AppKit)
                if let ns = object as? NSImage {
                    continuation.resume(returning: Image(nsImage: ns)); return
                }
                #endif
                continuation.resume(returning: nil)
            }
        }
    }
}

#if canImport(UIKit)
private typealias PlatformImage = UIImage
#elseif canImport(AppKit)
private typealias PlatformImage = NSImage
#endif
