# Recognition and source identity

## Verified toolchain boundary · 20 October 2026

The installed toolchain is Xcode 26.2 (17C52), with iPhoneOS SDK 26.2 and an app deployment target of 18.0. The paired demonstration device is an iPad mini (6th generation); its previously verified OS is iPadOS 26.5.

The installed PencilKit headers and Swift interfaces do not expose `PKStrokeRecognizer` or the new stable stroke UUID/selection APIs. Apple's [WWDC26 PencilKit session](https://developer.apple.com/videos/play/wwdc2026/203/) introduces those recognition and model-identity features for OS 27. The current build must not call them or infer durable identity from a stroke's array position.

## Selected-image path

For this toolchain, capture a bounded lasso image and use an image-capable OpenAI Responses model to extract text. Extraction is separate from interpretation: preserve negation, technical spelling and unclear tokens, report uncertainty, and let the user inspect/correct the result before research. An image answer without a reviewable transcript does not complete this flow.

The crop preview and nearby-context toggle define what is sent. Public research must receive only the separately reviewed public question. Do not send private canvas images or retrieved private passages as a public search query.

Source records use app-owned canvas/region identifiers, canvas bounds, drawing revision and a content hash. Before displaying or inserting a result, compare the captured source with the current source. A changed or deleted source makes the result stale. Only relocate an anchor when the same source content can be resolved without ambiguity. Accepted blocks retain their original source reference as history.

## Verification limits

Synthetic printed text, deterministic fixtures, simulated strokes and mocked HTTP responses test different parts of this pipeline. They do not establish Ben's handwriting accuracy, palm rejection, measured meeting usefulness or a supported end-to-end latency target.

Use the physical-device checklist in [DEMO.md](DEMO.md) for handwriting, acronyms, negation, erasure and diagrams. Keep recognition errors and stage timings with the tested app/model versions. No ≥80% usefulness or <10-second result is claimed without those measurements.

## Official API contracts checked

- [Image inputs](https://developers.openai.com/api/docs/guides/images-vision): Responses accepts image inputs; visual interpretation can fail, particularly on small or ambiguous text.
- [Structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs): schema-constrained extraction supports parsing, but does not establish transcription accuracy.
- [Web search](https://developers.openai.com/api/docs/guides/tools-web-search): preserve tool-supplied citation URLs/titles and inspect the actual source.
- [Pricing](https://developers.openai.com/api/docs/pricing): use reported usage and current service rates. The brief's illustrative session subtotal is not an app benchmark. Rates vary with processing mode and other inputs; local job caps are convenience controls.

The direct provider uses the already verified `gpt-6-luna` path. Account/model access and billing are separate from a ChatGPT subscription. A structured Responses router is an endpoint fallback; using the same model does not bypass unavailable model access. Offline examples provide an account-free interaction fallback, clearly labelled as fictional.
