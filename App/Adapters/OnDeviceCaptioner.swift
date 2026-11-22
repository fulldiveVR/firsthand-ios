#if os(iOS)
import CandidCore
import Foundation
import FoundationModels

/// Short caption from the on-device Apple Foundation Model. Text in, text out:
/// on iOS 26 the model takes no images, so Vision scene labels describe the photo.
/// Uses only `SystemLanguageModel.default`, which runs on the device. Never Private Cloud Compute.
/// Returns `nil` when Apple Intelligence is off, not supported, or not ready.
struct OnDeviceCaptioner: MomentCaptioner {
    static let maxLength = 80

    func caption(for context: CaptionContext) async -> String? {
        let model = SystemLanguageModel.default
        guard model.availability == .available, !context.sceneLabels.isEmpty || context.faceCount > 0 else { return nil }

        let session = LanguageModelSession(
            model: model,
            instructions: """
            You write one short, warm caption for a photo that a person shares with close friends.
            Use at most 8 words. No hashtags, no emoji, no quotes.
            Do not invent names, places, or events that the facts do not state.
            """
        )
        do {
            let response = try await session.respond(to: Self.prompt(context))
            return Self.clean(response.content)
        } catch {
            // Guardrail refusals, context limits, and model errors all mean "no caption".
            return nil
        }
    }

    static func prompt(_ c: CaptionContext) -> String {
        var facts = ["Scene: \(c.sceneLabels.prefix(6).joined(separator: ", "))"]
        if c.faceCount > 0 { facts.append("People in the photo: \(c.faceCount)") }
        if c.isNewPlace { facts.append("The person has not been at this place recently.") }
        return "Facts about the photo:\n" + facts.joined(separator: "\n")
    }

    static func clean(_ text: String) -> String? {
        let line = text
            .split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"“”")))
        guard let line, !line.isEmpty, line.count <= maxLength else { return nil }
        return line
    }
}
#endif
