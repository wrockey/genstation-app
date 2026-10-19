// PromptEnhancer.swift
// Prompt enhancement service using LLM APIs

import Foundation
import SwiftUI
import GenStationCore

// MARK: - Enhancement Models

enum EnhancementModel: String, CaseIterable, Identifiable {
    case geminiFlash = "gemini-2.0-flash"
    case geminiFlash25 = "gemini-2.5-flash"
    case gpt4oMini = "gpt-4o-mini"
    case claudeHaiku = "claude-3-5-haiku-20241022"
    case grokFast = "grok-3-mini"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .geminiFlash: return "Gemini 2.0 Flash"
        case .geminiFlash25: return "Gemini 2.5 Flash"
        case .gpt4oMini: return "GPT-4o Mini"
        case .claudeHaiku: return "Claude Haiku"
        case .grokFast: return "Grok 3 Mini"
        }
    }

    /// Model ID for xAI direct API (OpenAI-compatible)
    var xaiModelId: String {
        switch self {
        case .grokFast: return "grok-3-mini"  // xAI direct API model name
        default: return rawValue
        }
    }

    /// Model ID for AIML API
    var aimlModelId: String {
        switch self {
        case .grokFast: return "x-ai/grok-3-mini"  // AIML API format
        default: return rawValue
        }
    }

    /// Providers that support this model (in preference order)
    var supportedProviders: [EnhancementProvider] {
        switch self {
        case .geminiFlash, .geminiFlash25:
            return [.gemini, .aimlapi]  // Prefer native Gemini, fallback to AI/ML
        case .gpt4oMini, .claudeHaiku:
            return [.aimlapi]
        case .grokFast:
            return [.xai, .aimlapi]  // Prefer native xAI, fallback to AI/ML
        }
    }

    /// Display string showing available API providers
    var providerLabel: String {
        switch self {
        case .geminiFlash, .geminiFlash25:
            return "Gemini / AI·ML"
        case .gpt4oMini, .claudeHaiku:
            return "AI·ML API"
        case .grokFast:
            return "xAI / AI·ML"
        }
    }

    var speedIndicator: String {
        switch self {
        case .geminiFlash, .gpt4oMini, .claudeHaiku, .grokFast: return "Fast"
        case .geminiFlash25: return "Balanced"
        }
    }

    /// Determine which provider to use based on available API keys
    func selectProvider(geminiKey: String, aimlKey: String, grokKey: String = "") -> EnhancementProvider? {
        for provider in supportedProviders {
            switch provider {
            case .gemini where !geminiKey.isEmpty:
                return .gemini
            case .aimlapi where !aimlKey.isEmpty:
                return .aimlapi
            case .xai where !grokKey.isEmpty:
                return .xai
            default:
                continue
            }
        }
        return nil
    }

    /// Human-readable description of which keys are needed
    var requiredKeysDescription: String {
        switch self {
        case .geminiFlash, .geminiFlash25:
            return "Requires Gemini API key or AI/ML API key"
        case .gpt4oMini, .claudeHaiku:
            return "Requires AI/ML API key"
        case .grokFast:
            return "Requires Grok API key or AI/ML API key"
        }
    }
}

enum EnhancementProvider {
    case gemini
    case aimlapi
    case xai

    var privacyService: PrivacyService {
        switch self {
        case .gemini: return .gemini
        case .aimlapi: return .aimlapi
        case .xai: return .grok
        }
    }
}

// MARK: - Response Structures

private struct GeminiTextResponse: Codable {
    let candidates: [GeminiTextCandidate]?
    let error: GeminiError?
    let promptFeedback: GeminiTextPromptFeedback?
}

private struct GeminiTextCandidate: Codable {
    let content: GeminiTextContent?
    let finishReason: String?
    let safetyRatings: [GeminiTextSafetyRating]?
}

private struct GeminiTextContent: Codable {
    let parts: [GeminiTextPart]?
}

private struct GeminiTextPart: Codable {
    let text: String?
    let thought: Bool?
}

private struct GeminiError: Codable {
    let message: String?
    let code: Int?
}

private struct GeminiTextPromptFeedback: Codable {
    let blockReason: String?
    let safetyRatings: [GeminiTextSafetyRating]?
}

private struct GeminiTextSafetyRating: Codable {
    let category: String
    let probability: String
}

private struct AIMLChatResponse: Codable {
    let choices: [AIMLChoice]?
    let error: AIMLError?
}

private struct AIMLChoice: Codable {
    let message: AIMLMessage
}

private struct AIMLMessage: Codable {
    let content: String
}

private struct AIMLError: Codable {
    let message: String?
}

// MARK: - PromptEnhancer

class PromptEnhancer: ObservableObject {
    static let shared = PromptEnhancer()

    @Published var isEnhancing: Bool = false
    @Published var lastError: String? = nil

    // Last used model (persisted)
    @AppStorage("lastEnhancementModel", store: AppStorageContext.defaults) private var lastModelRaw: String = EnhancementModel.geminiFlash.rawValue

    var lastModel: EnhancementModel {
        get { EnhancementModel(rawValue: lastModelRaw) ?? .geminiFlash }
        set { lastModelRaw = newValue.rawValue }
    }

    private let systemPrompt = """
You are PromptStation, an expert prompt enhancer for AI image generation.

INPUT: A user's base prompt and zero or more style descriptors.

TASK: Create a single, cohesive enhanced prompt that:
1. Preserves the user's core subject and intent as the primary focus
2. Naturally integrates style descriptors into flowing prose
3. Adds relevant technical terms (lighting, composition, camera, mood)
4. Removes redundancy if user's prompt already contains style elements
5. Aims for 40-120 words—descriptive but not bloated

RULES:
- Never change the fundamental subject or scene
- Never add NSFW, violent, or inappropriate content
- Never mention artist names or copyrighted properties
- Never use phrases like "I enhanced" or explain what you did
- Return ONLY the enhanced prompt text, nothing else
"""

    private init() {}

    // MARK: - Batch Generation System Prompt

    private let batchSystemPrompt = """
You are a creative prompt generator for AI image generation.

INPUT: A description of what to generate and a target count.

TASK: Generate exactly the requested number of unique, detailed image prompts based on the description.

RULES:
- Each prompt should be self-contained and detailed (30-80 words)
- Vary perspectives, compositions, lighting, and moods across prompts
- Never include NSFW, violent, or inappropriate content
- Never mention artist names or copyrighted properties
- Return ONLY the prompts, one per line, numbered 1. 2. 3. etc.
- No explanations, headers, or other text
"""

    // MARK: - Public API

    /// Generate multiple batch prompts from a description
    /// - Parameters:
    ///   - description: Natural language description of what to generate
    ///   - count: Number of prompts to generate (1-50)
    ///   - model: The LLM model to use
    ///   - geminiKey: Gemini API key
    ///   - aimlKey: AI/ML API key
    ///   - grokKey: Grok/xAI API key
    /// - Returns: Array of generated prompt strings
    func generateBatch(
        description: String,
        count: Int,
        model: EnhancementModel,
        geminiKey: String,
        aimlKey: String,
        grokKey: String = ""
    ) async throws -> [String] {
        await MainActor.run {
            isEnhancing = true
            lastError = nil
        }

        defer {
            Task { @MainActor in
                isEnhancing = false
            }
        }

        // Build the user message for batch generation
        let userMessage = buildBatchUserMessage(description: description, count: count)

        // Select provider based on available API keys
        guard let provider = model.selectProvider(geminiKey: geminiKey, aimlKey: aimlKey, grokKey: grokKey) else {
            throw EnhancementError.missingAPIKey(model.requiredKeysDescription)
        }

        // Call selected API with batch system prompt
        let result: String
        switch provider {
        case .gemini:
            result = try await callGeminiForBatch(userMessage: userMessage, model: model, apiKey: geminiKey)
        case .aimlapi:
            result = try await callAIMLAPIForBatch(userMessage: userMessage, model: model, apiKey: aimlKey)
        case .xai:
            result = try await callXAIForBatch(userMessage: userMessage, model: model, apiKey: grokKey)
        }

        // Remember last used model
        lastModel = model

        // Parse the response into individual prompts
        return parseBatchResponse(result)
    }

    private func buildBatchUserMessage(description: String, count: Int) -> String {
        return "Generate \(count) unique image prompts for: \(description)"
    }

    private func parseBatchResponse(_ response: String) -> [String] {
        let lines = response.components(separatedBy: .newlines)
        return lines.compactMap { line -> String? in
            var cleaned = line.trimmingCharacters(in: .whitespaces)
            guard !cleaned.isEmpty else { return nil }

            // Remove numbering prefixes like "1.", "1)", "1:", etc.
            let numberPattern = #"^\d+[\.\)\:\-]\s*"#
            if let regex = try? NSRegularExpression(pattern: numberPattern, options: []) {
                let range = NSRange(location: 0, length: cleaned.utf16.count)
                cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
            }

            cleaned = cleaned.trimmingCharacters(in: .whitespaces)
            return cleaned.isEmpty ? nil : cleaned
        }
    }

    private func callGeminiForBatch(userMessage: String, model: EnhancementModel, apiKey: String) async throws -> String {
        let url = GeminiClient.generateContentURL(model: model.rawValue, apiKey: apiKey)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var generationConfig: [String: Any] = [
            "temperature": 0.9,
            "maxOutputTokens": 4000
        ]

        let isThinkingModel = model.rawValue.contains("2.5")
        if isThinkingModel {
            generationConfig["thinkingConfig"] = ["thinkingBudget": 0]
        }

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": batchSystemPrompt + "\n\n" + userMessage]
                    ]
                ]
            ],
            "generationConfig": generationConfig
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EnhancementError.networkError("Invalid response")
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let bodyString = String(data: data, encoding: .utf8) ?? "No body"
            Log.debug("Gemini batch generation error: \(httpResponse.statusCode) - \(bodyString)")
            throw EnhancementError.apiError("API error: \(httpResponse.statusCode)")
        }

        let decoded = try JSONDecoder().decode(GeminiTextResponse.self, from: data)

        if let error = decoded.error {
            throw EnhancementError.apiError(error.message ?? "Unknown Gemini error")
        }

        if let feedback = decoded.promptFeedback, let blockReason = feedback.blockReason {
            throw EnhancementError.apiError(formatEnhancementBlockReason(blockReason, safetyRatings: feedback.safetyRatings))
        }

        if let candidate = decoded.candidates?.first, let finishReason = candidate.finishReason,
           ["SAFETY", "RECITATION", "OTHER", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII"].contains(finishReason) {
            throw EnhancementError.apiError(formatEnhancementBlockReason(finishReason, safetyRatings: candidate.safetyRatings))
        }

        // Extract the non-thought text part
        guard let parts = decoded.candidates?.first?.content?.parts else {
            throw EnhancementError.emptyResponse
        }
        let textPart = parts.first(where: { $0.thought != true && $0.text != nil })
            ?? parts.first(where: { $0.text != nil })
        guard let text = textPart?.text else {
            throw EnhancementError.emptyResponse
        }

        return text
    }

    private func callAIMLAPIForBatch(userMessage: String, model: EnhancementModel, apiKey: String) async throws -> String {
        let url = AIMLEndpoints.chatCompletionsURL

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let requestBody: [String: Any] = [
            "model": model.aimlModelId,
            "messages": [
                ["role": "system", "content": batchSystemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "max_tokens": 4000,
            "temperature": 0.9
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EnhancementError.networkError("Invalid response")
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let bodyString = String(data: data, encoding: .utf8) ?? "No body"
            Log.debug("AIML batch generation error: \(httpResponse.statusCode) - \(bodyString)")
            throw EnhancementError.apiError("API error: \(httpResponse.statusCode)")
        }

        let decoded = try JSONDecoder().decode(AIMLChatResponse.self, from: data)

        if let error = decoded.error {
            throw EnhancementError.apiError(error.message ?? "Unknown API error")
        }

        guard let text = decoded.choices?.first?.message.content else {
            throw EnhancementError.emptyResponse
        }

        return text
    }

    private func callXAIForBatch(userMessage: String, model: EnhancementModel, apiKey: String) async throws -> String {
        var request = URLRequest(url: GrokClient.chatCompletionsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let auth = GrokClient.authorizationHeader(apiKey: apiKey)
        request.addValue(auth.value, forHTTPHeaderField: auth.name)

        let requestBody: [String: Any] = [
            "model": model.xaiModelId,
            "messages": [
                ["role": "system", "content": batchSystemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "max_tokens": 4000,
            "temperature": 0.9
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EnhancementError.networkError("Invalid response")
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let bodyString = String(data: data, encoding: .utf8) ?? "No body"
            Log.debug("xAI batch generation error: \(httpResponse.statusCode) - \(bodyString)")
            throw EnhancementError.apiError("API error: \(httpResponse.statusCode)")
        }

        let decoded = try JSONDecoder().decode(AIMLChatResponse.self, from: data)

        if let error = decoded.error {
            throw EnhancementError.apiError(error.message ?? "Unknown xAI error")
        }

        guard let text = decoded.choices?.first?.message.content else {
            throw EnhancementError.emptyResponse
        }

        return text
    }

    /// Enhance a prompt with optional styles
    /// - Parameters:
    ///   - prompt: The user's base prompt
    ///   - styles: Selected styles to integrate
    ///   - model: The LLM model to use
    ///   - geminiKey: Gemini API key (required for Gemini models)
    ///   - aimlKey: AI/ML API key (required for AIML models)
    ///   - grokKey: Grok/xAI API key (required for Grok models via xAI)
    /// - Returns: Enhanced prompt string
    func enhance(
        prompt: String,
        styles: [PromptStyle],
        model: EnhancementModel,
        geminiKey: String,
        aimlKey: String,
        grokKey: String = ""
    ) async throws -> String {
        await MainActor.run {
            isEnhancing = true
            lastError = nil
        }

        defer {
            Task { @MainActor in
                isEnhancing = false
            }
        }

        // Build the user message
        let userMessage = buildUserMessage(prompt: prompt, styles: styles)

        // Select provider based on available API keys
        guard let provider = model.selectProvider(geminiKey: geminiKey, aimlKey: aimlKey, grokKey: grokKey) else {
            throw EnhancementError.missingAPIKey(model.requiredKeysDescription)
        }

        // Call selected API
        let result: String
        switch provider {
        case .gemini:
            result = try await callGemini(userMessage: userMessage, model: model, apiKey: geminiKey)
        case .aimlapi:
            result = try await callAIMLAPI(userMessage: userMessage, model: model, apiKey: aimlKey)
        case .xai:
            result = try await callXAI(userMessage: userMessage, model: model, apiKey: grokKey)
        }

        // Remember last used model
        lastModel = model

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private Methods

    private func buildUserMessage(prompt: String, styles: [PromptStyle]) -> String {
        var message = "Base prompt: \(prompt)"

        if !styles.isEmpty {
            let styleDescriptions = styles.map { style -> String in
                // Extract just the style keywords (remove {prompt} placeholder)
                var description = style.prompt
                    .replacingOccurrences(of: "{prompt}", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if description.hasPrefix(". ") {
                    description = String(description.dropFirst(2))
                }
                return "\(style.name): \(description)"
            }
            message += "\n\nStyles to integrate:\n" + styleDescriptions.joined(separator: "\n")
        }

        return message
    }

    private func callGemini(userMessage: String, model: EnhancementModel, apiKey: String) async throws -> String {
        let url = GeminiClient.generateContentURL(model: model.rawValue, apiKey: apiKey)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var generationConfig: [String: Any] = [
            "temperature": 0.7,
            "maxOutputTokens": 1024
        ]

        // Gemini 2.5 models use thinking by default, which eats output tokens.
        // Disable it for simple prompt enhancement tasks.
        let isThinkingModel = model.rawValue.contains("2.5")
        if isThinkingModel {
            generationConfig["thinkingConfig"] = ["thinkingBudget": 0]
        }

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": systemPrompt + "\n\n" + userMessage]
                    ]
                ]
            ],
            "generationConfig": generationConfig
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EnhancementError.networkError("Invalid response")
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let bodyString = String(data: data, encoding: .utf8) ?? "No body"
            Log.debug("Gemini enhancement error: \(httpResponse.statusCode) - \(bodyString)")
            throw EnhancementError.apiError("API error: \(httpResponse.statusCode)")
        }

        let decoded = try JSONDecoder().decode(GeminiTextResponse.self, from: data)

        if let error = decoded.error {
            throw EnhancementError.apiError(error.message ?? "Unknown Gemini error")
        }

        // Check for prompt-level blocking
        if let feedback = decoded.promptFeedback, let blockReason = feedback.blockReason {
            throw EnhancementError.apiError(formatEnhancementBlockReason(blockReason, safetyRatings: feedback.safetyRatings))
        }

        // Check for candidate-level blocking
        if let candidate = decoded.candidates?.first, let finishReason = candidate.finishReason,
           ["SAFETY", "RECITATION", "OTHER", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII"].contains(finishReason) {
            throw EnhancementError.apiError(formatEnhancementBlockReason(finishReason, safetyRatings: candidate.safetyRatings))
        }

        // Extract the non-thought text part (2.5 models may return thought parts)
        guard let parts = decoded.candidates?.first?.content?.parts else {
            throw EnhancementError.emptyResponse
        }
        let textPart = parts.first(where: { $0.thought != true && $0.text != nil })
            ?? parts.first(where: { $0.text != nil })
        guard let text = textPart?.text else {
            throw EnhancementError.emptyResponse
        }

        return text
    }

    private func formatEnhancementBlockReason(_ reason: String, safetyRatings: [GeminiTextSafetyRating]?) -> String {
        var message: String

        switch reason {
        case "SAFETY":
            message = "Blocked for safety reasons"
        case "BLOCKLIST":
            message = "Blocked due to blocklist match"
        case "PROHIBITED_CONTENT":
            message = "Blocked: prohibited content"
        case "SPII":
            message = "Blocked: sensitive personal info"
        case "RECITATION":
            message = "Blocked: copyright concern"
        default:
            message = "Blocked: \(reason)"
        }

        if let ratings = safetyRatings {
            let high = ratings.filter { ["HIGH", "MEDIUM"].contains($0.probability) }
            if !high.isEmpty {
                let cats = high.map { $0.category.replacingOccurrences(of: "HARM_CATEGORY_", with: "").lowercased() }
                message += " (\(cats.joined(separator: ", ")))"
            }
        }

        return message
    }

    private func callAIMLAPI(userMessage: String, model: EnhancementModel, apiKey: String) async throws -> String {
        let url = AIMLEndpoints.chatCompletionsURL

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let requestBody: [String: Any] = [
            "model": model.aimlModelId,  // Use AIML-specific model ID
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "max_tokens": 500,
            "temperature": 0.7
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EnhancementError.networkError("Invalid response")
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let bodyString = String(data: data, encoding: .utf8) ?? "No body"
            Log.debug("AIML enhancement error: \(httpResponse.statusCode) - \(bodyString)")
            throw EnhancementError.apiError("API error: \(httpResponse.statusCode)")
        }

        let decoded = try JSONDecoder().decode(AIMLChatResponse.self, from: data)

        if let error = decoded.error {
            throw EnhancementError.apiError(error.message ?? "Unknown API error")
        }

        guard let text = decoded.choices?.first?.message.content else {
            throw EnhancementError.emptyResponse
        }

        return text
    }

    private func callXAI(userMessage: String, model: EnhancementModel, apiKey: String) async throws -> String {
        var request = URLRequest(url: GrokClient.chatCompletionsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let auth = GrokClient.authorizationHeader(apiKey: apiKey)
        request.addValue(auth.value, forHTTPHeaderField: auth.name)

        let requestBody: [String: Any] = [
            "model": model.xaiModelId,  // Use xAI-specific model ID
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "max_tokens": 500,
            "temperature": 0.7
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EnhancementError.networkError("Invalid response")
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let bodyString = String(data: data, encoding: .utf8) ?? "No body"
            Log.debug("xAI enhancement error: \(httpResponse.statusCode) - \(bodyString)")
            throw EnhancementError.apiError("API error: \(httpResponse.statusCode)")
        }

        // xAI uses OpenAI-compatible response format
        let decoded = try JSONDecoder().decode(AIMLChatResponse.self, from: data)

        if let error = decoded.error {
            throw EnhancementError.apiError(error.message ?? "Unknown xAI error")
        }

        guard let text = decoded.choices?.first?.message.content else {
            throw EnhancementError.emptyResponse
        }

        return text
    }
}

// MARK: - Errors

enum EnhancementError: LocalizedError {
    case missingAPIKey(String)
    case invalidURL
    case networkError(String)
    case apiError(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let msg): return msg
        case .invalidURL: return "Invalid API URL"
        case .networkError(let msg): return "Network error: \(msg)"
        case .apiError(let msg): return msg
        case .emptyResponse: return "Empty response from API"
        }
    }
}
