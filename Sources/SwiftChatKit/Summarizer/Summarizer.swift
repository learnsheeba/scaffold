import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Wraps Apple's on-device FoundationModels for the "Catch me up" feature.
/// Ignores tombstoned messages, uses only the latest edited text, and degrades
/// gracefully when the device lacks Apple Intelligence support.
public final class Summarizer {
    public enum Availability: Equatable {
        case available
        case unavailable(reason: String)
    }

    public init() {}

    public var availability: Availability {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(reason: "\(reason)")
        }
        #else
        return .unavailable(reason: "FoundationModels not available on this platform.")
        #endif
    }

    /// Build the prompt from the most recent 20 non-tombstoned messages,
    /// using each message's latest edited text.
    public func buildPrompt(from messages: [ChatMessage], limit: Int = 20) -> String {
        let recent = messages
            .filter { !$0.isDeleted }
            .sorted { $0.createdAt < $1.createdAt }
            .suffix(limit)

        let transcript = recent.compactMap { msg -> String? in
            guard let body = msg.summarizableText, !body.isEmpty else { return nil }
            let who = "User-\(msg.senderID.uuidString.prefix(4))"
            return "\(who): \(body)"
        }.joined(separator: "\n")

        return """
        Summarize the following chat conversation in 2-3 short sentences so a user \
        can quickly catch up. Focus on key topics and any decisions or questions.

        \(transcript)
        """
    }

    /// Generate a summary. Falls back to a naive extractive summary if the model
    /// is unavailable so the UI always has something to show.
    public func summarize(messages: [ChatMessage]) async -> String {
        let prompt = buildPrompt(from: messages)

        #if canImport(FoundationModels)
        if case .available = availability {
            do {
                let session = LanguageModelSession()
                let response = try await session.respond(to: prompt)
                return response.content
            } catch {
                return fallbackSummary(messages: messages)
            }
        }
        #endif

        return fallbackSummary(messages: messages)
    }

    /// Naive on-device fallback: last few non-deleted lines.
    public func fallbackSummary(messages: [ChatMessage]) -> String {
        let recent = messages
            .filter { !$0.isDeleted }
            .sorted { $0.createdAt < $1.createdAt }
            .suffix(3)
            .compactMap { $0.summarizableText }

        if recent.isEmpty {
            return "Summaries aren't available on this device, and there's nothing recent to recap."
        }
        return "Recent messages: " + recent.joined(separator: " · ")
    }
}
