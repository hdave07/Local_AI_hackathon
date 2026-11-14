import FlowCore
import Foundation
import Observation

@MainActor
@Observable
final class ClassifierViewModel {
    enum Phase: Equatable {
        case idle
        case classifying
        case interpreted(Intent, latency: Duration)
        case failed(ClassificationError)
    }

    enum ServerStatus: Equatable {
        case checking
        case ready(modelID: String)
        case modelNotLoaded(modelID: String, available: [String])
        case unavailable(String)
    }

    var command = ""
    private(set) var phase: Phase = .idle
    private(set) var serverStatus: ServerStatus = .checking

    let modelID: String
    private let classifier: any IntentClassifying
    private let listModels: @Sendable () async throws(ClassificationError) -> [String]
    private var task: Task<Void, Never>?

    init(
        classifier: any IntentClassifying,
        modelID: String,
        listModels: @escaping @Sendable () async throws(ClassificationError) -> [String]
    ) {
        self.classifier = classifier
        self.modelID = modelID
        self.listModels = listModels
    }

    var isBusy: Bool { phase == .classifying }

    func checkServer() async {
        serverStatus = .checking
        do throws(ClassificationError) {
            let models = try await listModels()
            serverStatus = models.contains(modelID)
                ? .ready(modelID: modelID)
                : .modelNotLoaded(modelID: modelID, available: models)
        } catch {
            serverStatus = .unavailable(error.userMessage)
        }
    }

    func submit() {
        let text = command
        task?.cancel()
        phase = .classifying
        task = Task { [classifier] in
            let clock = ContinuousClock()
            let start = clock.now
            let outcome: Phase
            do throws(ClassificationError) {
                let intent = try await classifier.classify(text)
                outcome = .interpreted(intent, latency: clock.now - start)
            } catch {
                outcome = .failed(error)
            }
            guard !Task.isCancelled else { return }
            self.phase = outcome
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        phase = .failed(.cancelled)
    }
}
