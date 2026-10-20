# Recognition and source identity

## Verified toolchain boundary · 20 October 2026

The installed toolchain is Xcode 26.2 (17C52), with iPhoneOS SDK 26.2 and an app deployment target of 18.0. The paired demonstration device is an iPad mini (6th generation); its previously verified OS is iPadOS 26.5.

The installed PencilKit headers and Swift interfaces do not expose `PKStrokeRecognizer` or the new stable stroke UUID/selection APIs. Apple's [WWDC26 PencilKit session](https://developer.apple.com/videos/play/wwdc2026/203/) introduces those recognition and model-identity features for OS 27. The current build must not call them or infer durable identity from a stroke's array position.

## Selected-image path

For this toolchain, capture a bounded lasso image and use an image-capable OpenAI Responses model to extract text. Extraction is separate from interpretation: preserve negation, technical spelling and unclear tokens, report uncertainty, and let the user inspect/correct the result before research. An image answer without a reviewable transcript does not complete this flow.

Tapping Ask Scout after lasso selection immediately starts transcription. The selected crop defines what is transcribed; a second snapshot covers the whole occupied canvas, including offscreen ink, typed content, attachments and AI block text. Both images are shown in the inspector and are scaled to at most 1,600 pixels on their longest side. Context is captured at selection time; later strokes are not streamed to the provider. Large canvas context can lose detail when scaled down. Recognition, routing and quick answers use this context. Explicit public research receives only the separately reviewed public question; Automatic research receives the recognised selected text. Do not send private canvas images or retrieved private passages as a public search query.

Source records use app-owned canvas/region identifiers, canvas bounds, drawing revision and a content hash. Before displaying or inserting a result, compare the captured source with the current source. A changed or deleted source makes the result stale. Only relocate an anchor when the same source content can be resolved without ambiguity. Accepted blocks retain their original source reference as history.

## Verification limits

Synthetic printed text, deterministic fixtures, simulated strokes and mocked HTTP responses test different parts of this pipeline. They do not establish Ben's handwriting accuracy, palm rejection, measured meeting usefulness or a supported end-to-end latency target.

Use the physical-device checklist in [DEMO.md](DEMO.md) for handwriting, acronyms, negation, erasure and diagrams. Keep recognition errors and stage timings with the tested app/model versions. No ≥80% usefulness or <10-second result is claimed without those measurements.

The [20 October physical-device report](device-reports/2026-10-20-real-handwriting.md) records the installed merged-main build and the pending/observed human sample outcomes for BIL-5 and BIL-9. Setup success alone does not satisfy their remaining criteria.

## Official API contracts checked

- [Image inputs](https://developers.openai.com/api/docs/guides/images-vision): Responses accepts image inputs; visual interpretation can fail, particularly on small or ambiguous text.
- [Structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs): schema-constrained extraction supports parsing, but does not establish transcription accuracy.
- [Web search](https://developers.openai.com/api/docs/guides/tools-web-search): preserve tool-supplied citation URLs/titles and inspect the actual source.
- [Pricing](https://developers.openai.com/api/docs/pricing): use reported usage and current service rates. The brief's illustrative session subtotal is not an app benchmark. Rates vary with processing mode and other inputs; local job caps are convenience controls.

The direct provider uses the already verified `gpt-6-luna` path. Account/model access and billing are separate from a ChatGPT subscription. A structured Responses router is an endpoint fallback; using the same model does not bypass unavailable model access. Offline examples provide an account-free interaction fallback, clearly labelled as fictional.

## Live automatic explanations · 20 October 2026

A runtime API key now enables OpenAI processing and Automatic mode by default; fictional offline examples require an explicit choice. Entering a new key enables live assistance. Forgetting the key, disabling processing or choosing Off stops live processing. Keys remain session-only.

A 1.8-second writing pause recognises a changed region with a whole-canvas context snapshot. Clear transcription routes automatically; stable quick explanations stream real Responses text events into a floating canvas card. Uncertain text waits for correction. In Automatic mode, a research decision uses the recognised selected text as its public research question; no canvas image is sent to web search. Explicit research retains the separate public-question review. Research answers are displayed only after citation/synthesis validation. Decisions selects the route before an automatic response card opens. A none decision leaves ordinary notes alone; clarify and uncertain handwriting retain a quiet Review control. This UI policy is covered by coordinator tests; real-world routing accuracy remains unmeasured. A 20-second cooldown defers the latest changed region instead of losing it.

Streaming uses `stream=true`, `response.output_text.delta` and `response.completed` from the [official Responses streaming contract](https://developers.openai.com/api/docs/guides/streaming-responses). Partial text is transient and cannot be inserted. Stop, cancellation, a changed source or a failed/truncated stream clears partial text. Completed requests retain reported token usage and timings. UI text updates are coalesced to protect drawing responsiveness; there is no simulated typewriter animation.

The Scout status opens an explanation and mode controls. “Watching notes” refers to handwriting changes; the app does not capture microphone audio. The bounded response card scrolls the complete transcript, answer and caveat, with Insert and Review outside the scrolling text. Both insertion paths validate the source and completed suggestion, use the same placement logic and create one undoable block.
