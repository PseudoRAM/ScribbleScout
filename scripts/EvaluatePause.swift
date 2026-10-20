import Foundation
import AppKit
import CoreText
import CryptoKit

// Synthetic diagnostic only. Uses the production provider; never calls answer or web search.
@main
struct EvaluatePause {
    struct Sample: Codable {
        let id, category, split, text, expectedRoute, image, provenance: String
        let useful: Bool
    }
    struct Manifest: Codable { let version: String; let frozenBeforeTuning: Bool; let samples: [Sample] }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func write(_ value: Any, to url: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: "docs/evaluations/pause-v1", isDirectory: true)
        let manifestData = try Data(contentsOf: root.appendingPathComponent("manifest.json"))
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        precondition(manifest.samples.count == 24 && Set(manifest.samples.map(\.id)).count == 24)
        precondition(manifest.frozenBeforeTuning)
        if CommandLine.arguments.contains("--prepare") {
            let images = root.appendingPathComponent("images")
            // Refuse replacement: a new rendering belongs in a new dataset version.
            try FileManager.default.createDirectory(at: images, withIntermediateDirectories: false)
            let fontURL = URL(fileURLWithPath: "ScribbleScout/Resources/Caveat.ttf")
            guard CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil),
                  let font = NSFont(name: "Caveat-Regular", size: 44) else { fatalError("Caveat font unavailable") }
            for sample in manifest.samples {
                let image = NSImage(size: NSSize(width: 1000, height: 260))
                image.lockFocus()
                NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1000, height: 260).fill()
                (sample.text as NSString).draw(in: NSRect(x: 30, y: 25, width: 940, height: 210),
                    withAttributes: [.font: font, .foregroundColor: NSColor.black])
                image.unlockFocus()
                guard let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { fatalError("Render failed") }
                try png.write(to: root.appendingPathComponent(sample.image), options: .withoutOverwriting)
            }
            var files = ["manifest.json": hash(manifestData)]
            for sample in manifest.samples { files[sample.image] = hash(try Data(contentsOf: root.appendingPathComponent(sample.image))) }
            try write(files, to: root.appendingPathComponent("inputs.sha256.json"))
            print("Frozen 24 synthetic images; 12 development / 12 held-out. No human handwriting.")
            return
        }
        guard CommandLine.arguments.contains("--run-heldout"), let outputIndex = CommandLine.arguments.firstIndex(of: "--output"),
              CommandLine.arguments.indices.contains(outputIndex + 1) else {
            print("Use --prepare, or --run-heldout --output <new-results.json>. Live runs are billable; no web search occurs.")
            return
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[outputIndex + 1])
        guard !FileManager.default.fileExists(atPath: output.path) else { fatalError("Refusing to overwrite results") }
        let hashes = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: root.appendingPathComponent("inputs.sha256.json")))
        for (path, expected) in hashes {
            let data = try Data(contentsOf: root.appendingPathComponent(path))
            precondition(hash(data) == expected, "Frozen input changed")
        }
        var key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
        if key.isEmpty, let file = try? String(contentsOfFile: ".env.local", encoding: .utf8) {
            for line in file.components(separatedBy: .newlines) {
                let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces) == "OPENAI_API_KEY" {
                    key = parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                }
            }
        }
        guard !key.isEmpty else { throw AssistanceError.missingKey }
        let provider = OpenAIAssistance(apiKey: key)
        var rows: [[String: Any]] = []
        var result: [String: Any] = ["dataset": manifest.version, "manifestSHA256": hash(manifestData),
            "startedUTC": ISO8601DateFormatter().string(from: Date()), "model": OpenAIAssistance.model,
            "minimumConfidence": OpenAIAssistance.minimumConfidence,
            "providerSHA256": hash(try Data(contentsOf: URL(fileURLWithPath: "ScribbleScout/Models/OpenAIAssistance.swift"))),
            "routingInstructionsSHA256": hash(Data(OpenAIAssistance.routingInstructions.utf8)),
            "runnerSHA256": hash(try Data(contentsOf: URL(fileURLWithPath: "scripts/EvaluatePause.swift"))),
            "scope": "Synthetic image recognition + routing only; pin is inferred from coordinator, not observed UI; no search or answers",
            "hostOS": ProcessInfo.processInfo.operatingSystemVersionString]
        for sample in manifest.samples where sample.split == "heldout" {
            var row: [String: Any] = ["id": sample.id, "expectedRoute": sample.expectedRoute, "useful": sample.useful]
            let start = Date()
            do {
                let recognition = try await provider.recognise(image: Data(contentsOf: root.appendingPathComponent(sample.image)))
                row["recognitionSeconds"] = Date().timeIntervalSince(start)
                row["transcript"] = recognition.text; row["uncertainty"] = recognition.uncertainty
                let routingStart = Date()
                let decision = try await provider.route(recognition.text)
                row["routingSeconds"] = Date().timeIntervalSince(routingStart)
                row["actualRoute"] = decision.route.rawValue
                row["fallback"] = decision.usedFallback
                row["confidence"] = decision.confidence ?? NSNull() as Any
                row["finalPinProxy"] = decision.route != .none && decision.route != .recall
                row["routeCorrect"] = decision.route.rawValue == sample.expectedRoute
            } catch {
                // Avoid provider bodies, headers and credentials in stored results.
                row["error"] = (error as? AssistanceError)?.localizedDescription ?? "Transport or local input failure"
            }
            row["pipelineSeconds"] = Date().timeIntervalSince(start)
            row["estimatedPauseToReviewSeconds"] = Date().timeIntervalSince(start) + 1.8
            rows.append(row); result["rows"] = rows
            try write(result, to: output)
            print("\(sample.id): \(row["actualRoute"] ?? row["error"] ?? "unknown")")
        }
        let usage = await provider.ledger.summary
        result["usage"] = ["requests": usage.requests, "inputTokens": usage.inputTokens,
                           "outputTokens": usage.outputTokens, "toolCalls": usage.toolCalls]
        result["completedUTC"] = ISO8601DateFormatter().string(from: Date())
        try write(result, to: output)
    }
}
