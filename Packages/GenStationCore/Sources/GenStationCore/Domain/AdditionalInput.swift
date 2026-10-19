import Foundation

/// Type of additional input binding
public enum AdditionalInputType: String, Codable, CaseIterable, Sendable {
    case text = "Text"
    case image = "Image"

    public var icon: String {
        switch self {
        case .text: return "text.alignleft"
        case .image: return "photo"
        }
    }
}

/// Represents an additional input binding for ComfyUI workflows
public struct AdditionalInput: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var inputType: AdditionalInputType
    public var boundNodeID: String
    public var boundInputKey: String
    public var displayName: String
    public var textValue: String?

    public init(
        id: UUID = UUID(),
        inputType: AdditionalInputType,
        boundNodeID: String = "",
        boundInputKey: String = "",
        displayName: String = ""
    ) {
        self.id = id
        self.inputType = inputType
        self.boundNodeID = boundNodeID
        self.boundInputKey = inputType == .text ? "text" : "image"
        self.displayName = displayName.isEmpty ? "Input \(inputType.rawValue)" : displayName
        self.textValue = inputType == .text ? "" : nil
    }
}
