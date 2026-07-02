import SwiftUI
import SwiftChatKit

/// Renders a single message bubble, handling text, photo, YouTube, tombstone,
/// and "(Edited)" states in the Apple Messages style.
public struct MessageBubbleView: View {
    public let message: ChatMessage
    public let isOutbound: Bool

    public init(message: ChatMessage, isOutbound: Bool) {
        self.message = message
        self.isOutbound = isOutbound
    }

    public var body: some View {
        HStack {
            if isOutbound { Spacer(minLength: 40) }
            VStack(alignment: isOutbound ? .trailing : .leading, spacing: 2) {
                bubbleContent
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(bubbleBackground)
                    .foregroundStyle(foreground)
                    .clipShape(MessageBubbleShape(isOutbound: isOutbound))

                if message.isEdited && !message.isDeleted {
                    Text("(Edited)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if !isOutbound { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if message.isDeleted {
            Label("This message was deleted", systemImage: "trash")
                .font(.body.italic())
                .foregroundStyle(.secondary)
        } else {
            switch message.kind {
            case .photo:
                if let path = message.mediaRelativePath {
                    DiskImageView(relativePath: path)
                        .frame(maxWidth: 220, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Text(message.text ?? "")
                }
            case .youtube:
                if let link = message.linkURL {
                    LinkPreviewView(urlString: link)
                        .frame(maxWidth: 260)
                }
            case .gameInvite:
                Label("Chess invite — tap to play", systemImage: "checkerboard.rectangle")
            default:
                Text(message.text ?? "")
                    .textSelection(.enabled)
            }
        }
    }

    private var bubbleBackground: some ShapeStyle {
        if message.isDeleted {
            return AnyShapeStyle(Color.gray.opacity(0.15))
        }
        if isOutbound {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.blue, Color.blue.opacity(0.85)],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
        return AnyShapeStyle(Color(white: 0.9))
    }

    private var foreground: Color {
        if message.isDeleted { return .secondary }
        return isOutbound ? .white : .primary
    }
}
