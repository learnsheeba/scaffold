import SwiftUI

/// Animated "user is typing" bubble with 3 staggered bouncing dots.
public struct TypingIndicatorView: View {
    @State private var bounce = false

    public init() {}

    public var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .frame(width: 8, height: 8)
                    .foregroundStyle(.secondary)
                    .offset(y: bounce ? -4 : 4)
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.15),
                        value: bounce
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(white: 0.9))
        .clipShape(MessageBubbleShape(isOutbound: false))
        .padding(.horizontal, 8)
        .onAppear { bounce = true }
    }
}

/// Tracks transient typing state with an automatic 3-second timeout.
@MainActor
public final class TypingState: ObservableObject {
    @Published public private(set) var isPeerTyping = false
    private var timeoutTask: Task<Void, Never>?

    public init() {}

    /// Call when a `.typing` frame arrives; resets the 3s countdown.
    public func peerDidType() {
        isPeerTyping = true
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.isPeerTyping = false
        }
    }
}
