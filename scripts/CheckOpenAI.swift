import Foundation
import AppKit

/// Run from the repo root. Prints only synthetic test results and returned public source metadata.
@main
struct CheckOpenAI {
    @MainActor
    static func main() async {
        do {
            var key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
            if key.isEmpty {
                let file = try String(contentsOfFile: ".env.local", encoding: .utf8)
                for line in file.components(separatedBy: .newlines) {
                    let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces) == "OPENAI_API_KEY" {
                        key = parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    }
                }
            }
            let provider = OpenAIAssistance(apiKey: key)
            if CommandLine.arguments.contains("--image") || CommandLine.arguments.contains("--recognition") {
                let picture = NSImage(size: NSSize(width: 420, height: 140))
                picture.lockFocus()
                NSColor.white.setFill()
                NSRect(x: 0, y: 0, width: 420, height: 140).fill()
                ("2 + 2 = ?" as NSString).draw(at: NSPoint(x: 30, y: 40), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black
                ])
                picture.unlockFocus()
                guard let tiff = picture.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                    throw AssistanceError.invalidInput
                }
                if CommandLine.arguments.contains("--recognition") {
                    let start = Date()
                    let result = try await provider.recognise(image: png)
                    let normalized = result.text.filter { !$0.isWhitespace }
                    guard normalized == "2+2=?" else {
                        // Only this generated arithmetic image is used in this mode; never print notebook text.
                        print("Synthetic extraction mismatch: \(result.text)")
                        throw AssistanceError.invalidResponse
                    }
                    let usage = await provider.ledger.summary
                    print("Synthetic printed-text extraction passed in \(String(format: "%.2f", Date().timeIntervalSince(start)))s; uncertainty items: \(result.uncertainty.count)")
                    print("Reported input/output tokens: \(usage.inputTokens)/\(usage.outputTokens); requests with unreported tokens: \(usage.unreportedTokenRequests)")
                    print("This does not measure real handwriting accuracy.")
                    return
                }
                let prompt = "Answer any question written in this selection; otherwise briefly explain the selected content. Reply with digits only."
                let route = try await provider.route(prompt, image: png)
                print("Synthetic image route: \(route.route.rawValue), confidence: \(route.confidence.map { String(format: "%.3f", $0) } ?? "fallback")")
                let answer = try await provider.answer(prompt, research: false, image: png)
                print("Synthetic arithmetic answer: \(answer.text)")
                guard route.route == .quickResponse,
                      answer.text.trimmingCharacters(in: .whitespacesAndNewlines) == "4" else { throw AssistanceError.invalidResponse }
                print("Synthetic selected-image test passed: Decisions routed to quick_response and Responses read the image correctly.")
                return
            }
            if CommandLine.arguments.contains("--routes") {
                let examples: [(String, AssistanceRoute)] = [
                    ("Explain what a database index is in simple terms.", .quickResponse),
                    ("Does Stripe Checkout support metered subscription billing in 2026? Find current official documentation.", .webResearch),
                    ("What did we decide last time about our checkout flow?", .recall),
                    ("Can it do that thing we mentioned?", .clarify),
                    ("Meeting note: the team will send the agenda on Friday.", .none),
                    ("Do not research Stripe Checkout. Just note that we are keeping the current flow.", .none)
                ]
                for (input, expected) in examples {
                    let result = try await provider.route(input)
                    print("Expected \(expected.rawValue); received \(result.route.rawValue); confidence \(result.confidence.map { String(format: "%.3f", $0) } ?? "fallback")")
                    guard result.route == expected else { throw AssistanceError.invalidResponse }
                }
                return
            }
            let start = Date()
            let decision = try await provider.route("Explain what a database index is in simple terms.")
            print("Route: \(decision.route.rawValue); fallback: \(decision.usedFallback); \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
            guard decision.route == .quickResponse else { throw AssistanceError.invalidResponse }
            let quick = try await provider.answer("Explain what a database index is in simple terms.", research: false)
            print("Quick answer: \(quick.text.count) characters; no web tools supplied")
            let research = try await provider.answer("Find the official OpenAI documentation for the Decisions API. Summarize its purpose in one sentence with a citation.", research: true)
            print("Research: \(research.citations.count) cited sources")
            for source in research.citations { print("\(source.title): \(source.url.absoluteString)") }
            let usage = await provider.ledger.summary
            print("Session requests: \(usage.requests); reported input/output tokens: \(usage.inputTokens)/\(usage.outputTokens); tools: \(usage.toolCalls); partial-token requests: \(usage.unreportedTokenRequests)")
        } catch {
            // Never dump provider bodies, request headers, environment variables, or the credential.
            print((error as? AssistanceError)?.localizedDescription ?? "Live check failed. Check network access to api.openai.com and retry.")
            exit(1)
        }
    }
}
