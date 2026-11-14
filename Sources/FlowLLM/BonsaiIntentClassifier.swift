import FlowCore
import Foundation

/// Intent classification using Bonsai 2 served by LM Studio.
///
/// Pipeline: input checks → deterministic control phrases (no model) →
/// schema-constrained completion → strict validation. Retries once on transient
/// output problems only (spec 02 §18 ERR-01). Never executes anything.
public struct BonsaiIntentClassifier: IntentClassifying {
    public static let maxInputLength = 500

    private let client: LMStudioClient
    private let maxAttempts: Int

    public init(client: LMStudioClient, maxAttempts: Int = 2) {
        self.client = client
        self.maxAttempts = max(1, maxAttempts)
    }

    public var modelID: String { client.configuration.modelID }

    public func classify(_ utterance: String) async throws(ClassificationError) -> Intent {
        let input = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { throw .emptyInput }
        guard input.count <= Self.maxInputLength else { throw .inputTooLong(limit: Self.maxInputLength) }

        if let control = DeterministicRouter.route(input) { return control }

        let messages = [
            ChatMessage(role: .system, content: IntentSchema.systemPrompt),
            ChatMessage(role: .user, content: input),
        ]

        var lastError: ClassificationError = .emptyResponse
        for _ in 0..<maxAttempts {
            if Task.isCancelled { throw .cancelled }
            do {
                let result = try await client.complete(
                    messages: messages, schemaName: IntentSchema.name, schema: IntentSchema.jsonSchema)
                return try IntentValidator.validate(result.content, modelID: result.modelID)
            } catch {
                lastError = error
                guard error.retrySafe else { throw error }
            }
        }
        throw lastError
    }
}
