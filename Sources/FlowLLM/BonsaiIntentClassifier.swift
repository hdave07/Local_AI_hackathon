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
    /// System prompt sent with every request (default `IntentSchema.systemPrompt`).
    public let systemPrompt: String

    public init(client: LMStudioClient, maxAttempts: Int = 2, systemPrompt: String = IntentSchema.systemPrompt) {
        self.client = client
        self.maxAttempts = max(1, maxAttempts)
        self.systemPrompt = systemPrompt
    }

    public var modelID: String { client.configuration.modelID }

    public func classify(_ utterance: String) async throws(ClassificationError) -> Intent {
        try await classifyTraced(utterance).outcome.get()
    }

    /// Same pipeline as `classify`, also returning each model attempt's raw output and
    /// latency (for T-002 benchmarking and diagnostics). Raw output is untrusted.
    public func classifyTraced(_ utterance: String) async -> ClassificationTrace {
        let input = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return ClassificationTrace(outcome: .failure(.emptyInput), attempts: []) }
        guard input.count <= Self.maxInputLength else {
            return ClassificationTrace(outcome: .failure(.inputTooLong(limit: Self.maxInputLength)), attempts: [])
        }

        if let control = DeterministicRouter.route(input) {
            return ClassificationTrace(outcome: .success(control), attempts: [])
        }

        let messages = [
            ChatMessage(role: .system, content: systemPrompt),
            ChatMessage(role: .user, content: input),
        ]

        var attempts: [ClassificationTrace.Attempt] = []
        var lastError: ClassificationError = .emptyResponse
        for _ in 0..<maxAttempts {
            if Task.isCancelled { return ClassificationTrace(outcome: .failure(.cancelled), attempts: attempts) }
            let started = ContinuousClock.now
            var raw: String?
            do {
                let result = try await client.complete(
                    messages: messages, schemaName: IntentSchema.name, schema: IntentSchema.jsonSchema)
                raw = result.content
                let intent = try IntentValidator.validate(result.content, modelID: result.modelID)
                attempts.append(.init(rawContent: raw, error: nil, latency: ContinuousClock.now - started))
                return ClassificationTrace(outcome: .success(intent), attempts: attempts)
            } catch {
                attempts.append(.init(rawContent: raw, error: error, latency: ContinuousClock.now - started))
                lastError = error
                guard error.retrySafe else { break }
            }
        }
        return ClassificationTrace(outcome: .failure(lastError), attempts: attempts)
    }
}

/// Result of one classification plus per-attempt evidence.
public struct ClassificationTrace: Sendable {
    public struct Attempt: Sendable {
        /// The model's raw message content, if a response arrived.
        public let rawContent: String?
        public let error: ClassificationError?
        public let latency: Duration

        public init(rawContent: String?, error: ClassificationError?, latency: Duration) {
            self.rawContent = rawContent
            self.error = error
            self.latency = latency
        }
    }

    public let outcome: Result<Intent, ClassificationError>
    /// Empty when no model call was needed (input checks or deterministic control phrase).
    public let attempts: [Attempt]

    public init(outcome: Result<Intent, ClassificationError>, attempts: [Attempt]) {
        self.outcome = outcome
        self.attempts = attempts
    }
}
