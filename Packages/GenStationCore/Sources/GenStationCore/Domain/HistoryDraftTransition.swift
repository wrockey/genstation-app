import Foundation

public enum HistoryDraftTransition {
    public struct Destination: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let provider: Provider
        public let task: CreateTask
    }
    public static func destinations(task: CreateTask) -> [Destination] {
        let native: [Destination] = task == .image ? [
            Destination(id: "gemini-3-pro-image-preview", name: "Gemini 3 Pro Image", provider: .gemini, task: .image),
            Destination(id: "grok-imagine-image-2.0", name: "Grok Imagine Image 2.0", provider: .grok, task: .image)
        ] : [Destination(id: GrokVideoClient.model, name: "Grok Imagine Video", provider: .grok, task: .video)]
        return native + Catalog.all.filter {
            ReleaseModelPolicy.allows($0.id, task: task) && $0.isI2I && $0.maxInputImages > 0
        }.sorted { $0.displayName < $1.displayName }.map {
            Destination(id: $0.id, name: $0.displayName, provider: $0.provider, task: task)
        }
    }
    public static func issue(destination: Destination, prompt: String, occupiedInputs: Int, sourceReadable: Bool) -> String? {
        guard destinations(task: destination.task).contains(destination) else { return ReleaseModelPolicy.unavailableMessage }
        guard sourceReadable else { return "The original image is missing or unreadable. Locate or restore it before preparing a draft." }
        guard occupiedInputs == 0, prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Your creation form already contains work. Save or clear the prompt and remove current input images before preparing this draft."
        }
        return nil
    }
}
