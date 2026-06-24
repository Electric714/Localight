//
//  ChatViewModel_27.swift
//  Localight
//
//  Created by Timo Köthe on 10.06.26.
//

import Foundation
import UIKit

#if compiler(>=6.2)
// MARK: - iOS 27+ Implementation (requires Xcode 27+)
import FoundationModels

@Observable
class ChatViewModel_27 {
    private var session: LanguageModelSession
    private var options: GenerationOptions
    private var accumulatedInputTokens = 0
    private var accumulatedOutputTokens = 0

    var instructions: String
    var instructionsDraft: String
    var temperature: Double
    var temperatureDraft: Double
    let contextSize: Int
    var contextTokensUsed: Int
    var inputText: String
    var attachedImage: UIImage?
    var prompt: String
    var isResponding: Bool
    var isStreaming: Bool
    var showsMessageTokenUsage: Bool
    var showsGenerationError: Bool
    var generationErrorTitle: String
    var generationErrorMessage: String
    var messages: [Message_27]
    var streamingResponse: String

    var hasInstructionChanges: Bool {
        let trimmed = instructionsDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != instructions
    }

    var hasTemperatureChanges: Bool {
        temperatureDraft != temperature
    }

    init() {
        let defaultInstructions = "Act as the best buddie. Keep your answer short."
        self.session = LanguageModelSession(instructions: defaultInstructions)
        self.options = GenerationOptions(temperature: 1.0)
        self.instructions = defaultInstructions
        self.instructionsDraft = defaultInstructions
        self.temperature = 1.0
        self.temperatureDraft = 1.0
        self.contextSize = SystemLanguageModel.default.contextSize
        self.contextTokensUsed = 0
        self.inputText = ""
        self.attachedImage = nil
        self.prompt = ""
        self.isResponding = false
        self.isStreaming = false
        self.showsMessageTokenUsage = true
        self.showsGenerationError = false
        self.generationErrorTitle = ""
        self.generationErrorMessage = ""
        self.messages = []
        self.streamingResponse = ""
        self.session.prewarm()

        Task {
            await updateInstructionTokenCount()
        }
    }

    func getResponse() async {
        let image = await preparePrompt()
        var modelMessageIndex: Int?
        defer { isResponding = false }

        do {
            let response = try await respond(with: image)
            messages.append(Message_27(text: response.content, sender: .model))
            modelMessageIndex = messages.index(before: messages.endIndex)
        } catch {
            presentGenerationError(error)
        }

        updateTokenUsage(for: modelMessageIndex)
    }

    func streamResponse() async {
        let image = await preparePrompt()
        let stream = responseStream(with: image)
        var modelMessageIndex: Int?
        defer {
            streamingResponse = ""
            isResponding = false
        }

        do {
            for try await chunk in stream {
                streamingResponse = chunk.content
            }
            let response = try await stream.collect()
            messages.append(Message_27(text: response.content, sender: .model))
            modelMessageIndex = messages.index(before: messages.endIndex)
        } catch {
            presentGenerationError(error)
        }

        updateTokenUsage(for: modelMessageIndex)
    }

    func applyInstructions() {
        let trimmed = instructionsDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        instructions = trimmed
        instructionsDraft = trimmed
        resetSession()
    }

    func applyTemperature() {
        temperature = temperatureDraft
        resetSession()
    }

    func attachImageData(_ data: Data) {
        attachedImage = UIImage(data: data)
    }

    func removeAttachment() {
        attachedImage = nil
    }

    func resetSession() {
        session = LanguageModelSession(instructions: instructions)
        options = GenerationOptions(temperature: temperature)
        inputText = ""
        attachedImage = nil
        prompt = ""
        isResponding = false
        isStreaming = false
        showsGenerationError = false
        generationErrorTitle = ""
        generationErrorMessage = ""
        messages = []
        streamingResponse = ""
        contextTokensUsed = 0
        accumulatedInputTokens = 0
        accumulatedOutputTokens = 0

        Task {
            await updateInstructionTokenCount()
        }
    }

    private func preparePrompt() async -> UIImage? {
        isResponding = true
        let image = attachedImage
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        messages.append(Message_27(text: trimmedInput, sender: .user, image: image))
        let messageIndex = messages.index(before: messages.endIndex)
        prompt = trimmedInput.isEmpty ? "Describe this image." : trimmedInput
        inputText = ""
        attachedImage = nil

        messages[messageIndex].tokenCount = try? await SystemLanguageModel.default.tokenCount(for: prompt)
        return image
    }

    private func respond(with image: UIImage?) async throws -> LanguageModelSession.Response<String> {
        guard let cgImage = image?.cgImage else {
            return try await session.respond(to: prompt, options: options)
        }
        return try await session.respond(options: options) {
            prompt
            Attachment<ImageAttachmentContent>(cgImage)
        }
    }

    private func responseStream(with image: UIImage?) -> LanguageModelSession.ResponseStream<String> {
        guard let cgImage = image?.cgImage else {
            return session.streamResponse(to: prompt, options: options)
        }
        return session.streamResponse(options: options) {
            prompt
            Attachment<ImageAttachmentContent>(cgImage)
        }
    }

    private func presentGenerationError(_ error: Error) {
        let errorMessage = generationErrorMessage(for: error)
        generationErrorTitle = errorMessage.title
        generationErrorMessage = errorMessage.message
        showsGenerationError = true
    }

    private func generationErrorMessage(for error: Error) -> (title: String, message: String) {
        if let languageModelError = error as? LanguageModelError {
            switch languageModelError {
            case .contextSizeExceeded(_):
                return ("Context window exceeded", "The current chat is too long for the on-device model.")
            case .rateLimited(_):
                return ("Model is rate limited", "The session is temporarily rate limited.")
            case .refusal(_):
                return ("Model refused", "The model declined to answer this request.")
            case .timeout(_):
                return ("Request timed out", "The model did not finish the response in time.")
            case .guardrailViolation(_):
                return ("Safety guardrail triggered", "The prompt triggered safety guardrails.")
            default:
                return ("Model error", error.localizedDescription)
            }
        }
        return ("Response failed", error.localizedDescription)
    }

    private func updateInstructionTokenCount() async {
        let tokenCount = try? await SystemLanguageModel.default.tokenCount(for: Instructions(instructions))
        if messages.isEmpty {
            contextTokensUsed = tokenCount ?? 0
        }
    }

    private func updateTokenUsage(for messageIndex: Int?) {
        let currentUsage = session.usage
        let inputTokens = currentUsage.input.totalTokenCount
        let outputTokens = currentUsage.output.totalTokenCount

        let newInputTokens = inputTokens - accumulatedInputTokens
        let newOutputTokens = outputTokens - accumulatedOutputTokens
        accumulatedInputTokens = inputTokens
        accumulatedOutputTokens = outputTokens

        guard newInputTokens + newOutputTokens > 0 else { return }

        contextTokensUsed = newInputTokens + newOutputTokens
        if let messageIndex {
            messages[messageIndex].tokenCount = newOutputTokens
        }
    }
}

#else
// MARK: - Fallback Implementation for older Xcode (Xcode 26.x)
// Provides basic functionality without iOS 27-only APIs

@Observable
class ChatViewModel_27 {
    var instructions: String = "Act as the best buddie. Keep your answer short."
    var instructionsDraft: String = "Act as the best buddie. Keep your answer short."
    var temperature: Double = 1.0
    var temperatureDraft: Double = 1.0
    let contextSize: Int = 4096
    var contextTokensUsed: Int = 0
    var inputText: String = ""
    var attachedImage: UIImage?
    var prompt: String = ""
    var isResponding: Bool = false
    var isStreaming: Bool = false
    var showsMessageTokenUsage: Bool = false
    var showsGenerationError: Bool = false
    var generationErrorTitle: String = ""
    var generationErrorMessage: String = ""
    var messages: [Message_27] = []
    var streamingResponse: String = ""

    var hasInstructionChanges: Bool {
        let trimmed = instructionsDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != instructions
    }

    var hasTemperatureChanges: Bool {
        temperatureDraft != temperature
    }

    func getResponse() async {
        // Basic fallback - just echo for now
        isResponding = true
        let userText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        messages.append(Message_27(text: userText, sender: .user))
        inputText = ""
        attachedImage = nil

        // Simulate response
        try? await Task.sleep(for: .seconds(1))
        messages.append(Message_27(text: "[iOS 27 features require newer Xcode]", sender: .model))
        isResponding = false
    }

    func streamResponse() async {
        await getResponse()
    }

    func applyInstructions() {
        instructions = instructionsDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        resetSession()
    }

    func applyTemperature() {
        temperature = temperatureDraft
        resetSession()
    }

    func attachImageData(_ data: Data) {
        attachedImage = UIImage(data: data)
    }

    func removeAttachment() {
        attachedImage = nil
    }

    func resetSession() {
        inputText = ""
        attachedImage = nil
        prompt = ""
        isResponding = false
        isStreaming = false
        showsGenerationError = false
        messages = []
        streamingResponse = ""
        contextTokensUsed = 0
    }
}
#endif
