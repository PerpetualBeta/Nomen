import Foundation
import Vision
import NomenCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Works out a name for one screenshot.
///
/// Everything here runs on this Mac. Text comes from Vision, and the name comes from the
/// on-device `SystemLanguageModel`. The framework also offers a Private Cloud Compute model;
/// Nomen never uses it, because "nothing leaves your Mac" is the reason Nomen exists.
///
/// The best path is chosen per screenshot from what the Mac can do:
/// - macOS 27 with a model that has the vision capability: the image itself plus its text.
/// - macOS 26: the recognised text only.
/// - otherwise, or if the model fails: `RuleNamer`, built from the app name and the text.
enum Namer {

    struct Result {
        let stem: String
        let method: String
    }

    /// How long the model may take before the rules name the file instead. Measured
    /// replies took 0.5 to 1.8 seconds; this is generous so a busy Mac is not punished,
    /// and bounded so a stuck model cannot hold a screenshot's name for ever.
    static let modelTimeout: TimeInterval = 20

    /// Characters of recognised text given to the model. A dense screenshot can hold
    /// thousands, the model's context is small, and the name comes from the top anyway.
    static let textBudget = 1500

    /// Naming takes two calls: describe the screenshot, then name the description.
    ///
    /// One call asking for a filename straight from the image did not work. Told to use
    /// "words that appear in it", the model leaned on the text and the app name and all but
    /// ignored the picture: a text-free aerial photo of the Pentagon came back `main-image`,
    /// although the same model, asked to describe the same file, said "An aerial view of the
    /// Pentagon building in Washington, D.C." Measured on nine real screenshots, describing
    /// first gave the better name in every case but one tie, for about half a second more.
    ///
    /// Both prompts are live knobs, so they can be tuned without a rebuild:
    ///   defaults write cc.jorviksoftware.Nomen describeInstructions "…"
    ///   defaults write cc.jorviksoftware.Nomen namingInstructions "…"
    ///   defaults delete cc.jorviksoftware.Nomen describeInstructions   # back to the default
    /// The app the capture came from is context, not content. Passed as plain "App: X", the
    /// model treated it as part of the picture, and a photo read in a news app became
    /// `jorvik-daily-news-tablet-speaker`. Saying what the app line is for, and leaving it out
    /// of the naming step, keeps it for the cases where the app is the subject (its error,
    /// its settings, a conversation in it) and drops it from photos. Jonathan's call,
    /// 2026-10-01.
    static let defaultDescribeInstructions = """
    Describe what this screenshot mainly shows in one sentence. Be specific: name the place, \
    product, person, document, error or topic if you can identify it. Do not add details you \
    cannot see. The app the screenshot was taken in is given for context only: mention it \
    only if the screenshot is about that app itself, such as its error message, settings or \
    a conversation in it.
    """

    static let defaultNamingInstructions = """
    You turn a description of a screenshot into a filename. Reply with ONE filename slug \
    only: 3 to 7 lowercase words joined by hyphens, no extension, no quotes, no explanation. \
    Keep the most specific words. Do not use the words screenshot, image, picture or app.
    """

    static var describeInstructions: String { knob("describeInstructions", or: defaultDescribeInstructions) }
    static var namingInstructions: String { knob("namingInstructions", or: defaultNamingInstructions) }

    private static func knob(_ key: String, or fallback: String) -> String {
        let custom = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (custom?.isEmpty ?? true) ? fallback : custom!
    }

    // MARK: - Availability

    enum ModelState: Equatable {
        case imageAndText
        case textOnly
        case unavailable(String)
    }

    static var modelState: ModelState {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                if #available(macOS 27, *), model.capabilities.contains(.vision) { return .imageAndText }
                return .textOnly
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable("Apple Intelligence is turned off")
            case .unavailable(.deviceNotEligible):
                return .unavailable("this Mac cannot run Apple Intelligence")
            case .unavailable(.modelNotReady):
                return .unavailable("the model is still downloading")
            case .unavailable:
                return .unavailable("the model is unavailable")
            }
        }
        #endif
        return .unavailable("it needs macOS 26 or later")
    }

    // MARK: - Naming

    static func name(imageAt url: URL, context: CaptureContext.Context) async -> Result? {
        let text = await recogniseText(at: url)
        switch modelState {
        case .unavailable(let reason):
            nmLog("namer: model unavailable (\(reason)); using rules")
        case .imageAndText:
            if let stem = await modelName(url: url, text: text, context: context, useImage: true) {
                return finished(stem, method: "model", context: context)
            }
        case .textOnly:
            if let stem = await modelName(url: url, text: text, context: context, useImage: false) {
                return finished(stem, method: "model (text)", context: context)
            }
        }
        if let stem = RuleNamer.name(appName: context.appName, recognisedText: text) {
            return finished(stem, method: "rules", context: context)
        }
        return nil
    }

    /// The name with any web browser's name taken out: the screenshot is of the page, not the
    /// browser. See `BrowserName`. Applied to every path, the rules included, which put the app
    /// name first by design.
    private static func finished(_ stem: String, method: String, context: CaptureContext.Context) -> Result {
        let cleaned = BrowserName.strip(stem, appName: context.appName)
        if cleaned != stem { nmLog("namer: removed the browser's name: \(stem) -> \(cleaned)") }
        return Result(stem: cleaned, method: method)
    }

    /// Recognises text on a background thread. Vision's first request in a process loads
    /// its models, which took 32 seconds on a measured cold start, so `warmUp` runs one at
    /// launch to keep that wait away from the user's first screenshot.
    static func recogniseText(at url: URL) async -> String {
        await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            do {
                try VNImageRequestHandler(url: url).perform([request])
            } catch {
                nmLog("namer: OCR failed: \(error.localizedDescription)")
                return ""
            }
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }.value
    }

    static func warmUp() {
        Task.detached(priority: .utility) {
            let start = Date()
            let size = 64
            guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let image = ctx.makeImage() else { return }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            try? VNImageRequestHandler(cgImage: image).perform([request])
            nmLog(String(format: "namer: Vision warmed up in %.1fs", Date().timeIntervalSince(start)))
        }
    }

    private static func modelName(url: URL, text: String, context: CaptureContext.Context, useImage: Bool) async -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            var lines: [String] = []
            if let app = context.appName { lines.append("Taken in the app: \(app)") }
            if let title = context.windowTitle { lines.append("Window title: \(title)") }
            let excerpt = String(text.prefix(textBudget))
            lines.append(excerpt.isEmpty ? "No readable text." : "Text in the screenshot:\n\(excerpt)")
            let promptText = lines.joined(separator: "\n")
            let describe = describeInstructions
            let naming = namingInstructions
            let start = Date()
            // One timeout covers both calls: what is bounded is the user's wait for a name.
            let reply: (description: String, name: String)? = await withTimeout(modelTimeout) {
                let options = GenerationOptions(temperature: 0.2)
                let describer = LanguageModelSession(model: .default, instructions: describe)
                let description: String
                if useImage, #available(macOS 27, *) {
                    description = try await describer.respond(options: options) {
                        promptText
                        Attachment(imageURL: url)
                    }.content
                } else {
                    description = try await describer.respond(to: promptText, options: options).content
                }
                // A failed describe call must throw, never reach this step as text: an error
                // message used as a "description" got a file named after the path inside it.
                // `respond` throws on failure; an empty reply is treated the same way.
                guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw EmptyDescription()
                }
                let namer = LanguageModelSession(model: .default, instructions: naming)
                let name = try await namer.respond(to: "Description: \(description)", options: options).content
                return (description, name)
            }
            let elapsed = Date().timeIntervalSince(start)
            guard let reply else {
                nmLog(String(format: "namer: model gave no reply in %.1fs", elapsed))
                return nil
            }
            let stem = Slug.make(from: reply.name)
            // Lengths, never the text. The description is what the screenshot shows, and on
            // 2026-10-08 a 1Password card's description put a database password into this log.
            // The final name is logged because the renamed file already carries it on disk.
            nmLog(String(format: "namer: model replied in %.1fs: %d-character description, %d-character name -> %@",
                         elapsed, reply.description.count, reply.name.count, stem ?? "(unusable)"))
            return stem
        }
        #endif
        return nil
    }

    /// Runs `work` and returns its value, or nil if it throws or takes longer than
    /// `seconds`. The timeout really bounds the wait: the caller resumes as soon as either
    /// side finishes, and a late reply is discarded. A task group would not do this, because
    /// it waits for a cancelled child to finish before returning.
    private static func withTimeout<T: Sendable>(_ seconds: TimeInterval,
                                                 _ work: @escaping @Sendable () async throws -> T) async -> T? {
        let gate = ResumeOnce<T?>()
        return await withCheckedContinuation { continuation in
            gate.set(continuation)
            let task = Task {
                // The error is logged, not just dropped. `try?` used to turn every failure into
                // "the model gave no reply", so two names on 2026-10-05 fell back to the rules
                // after 1.7 s and 1.9 s, well inside the timeout, and the log could not say why.
                do {
                    gate.resume(try await work())
                } catch {
                    // Only if this branch ended the wait: once the timeout has won, the work is
                    // cancelled and its CancellationError is the timeout's echo, not a cause.
                    if gate.resume(nil) {
                        // The error's type and its plain message say why ("The model's safety
                        // guardrails were triggered"). Not `String(describing:)`, whose debug
                        // context could carry the prompt, and the prompt holds the description.
                        nmLog("namer: model call failed: \(type(of: error)): \(error.localizedDescription)")
                    }
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                task.cancel()
                if gate.resume(nil) {
                    nmLog(String(format: "namer: model call timed out after %.0fs", seconds))
                }
            }
        }
    }
}

/// The describe step answered with nothing. Thrown so that it is logged as itself, where it used
/// to be a CancellationError and read like the timeout.
private struct EmptyDescription: Error, CustomStringConvertible {
    var description: String { "the model described the screenshot with an empty reply" }
}

/// Resumes a continuation exactly once, whichever caller gets there first.
private final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?

    func set(_ c: CheckedContinuation<T, Never>) {
        lock.lock(); continuation = c; lock.unlock()
    }

    /// Whether this call was the one that resumed it.
    @discardableResult
    func resume(_ value: T) -> Bool {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(returning: value)
        return c != nil
    }
}
