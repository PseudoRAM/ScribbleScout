# Pause assistance held out diagnostic

**Recommendation: use Explicit only for the essential demo. Do not present Automatic as validated for handwriting.** The frozen synthetic diagnostic produced unwanted final pins on 4 of 6 regions labelled quiet, despite correct transcription. Explicit request priority and the reviewed public query boundary passed the frozen coordinator checks. No prompt, confidence threshold, pause or cooldown was tuned.

BIL-18 is partially evaluated; its real-handwriting acceptance criterion remains open. BIL-29's 20–30 human regions, manual citation checking and broader diagnostic remain outstanding. There were no existing human samples available; the user confirmed this. Prepared examples are fictional font renderings, not captured handwriting.

## Inputs and versions

Run date: 20 October 2026, Australia/Sydney. Starting app commit: `dfc4b8f72c0481370de11de751ed8417987aec6b`, app 0.1.0 build 1. See [versions.json](versions.json) for source hashes and simulator version. Provider: `gpt-6-luna`, confidence gate 0.75, unchanged recognition/routing prompts. Model name is an alias, not a pinned server snapshot. Results are one stochastic run, not a calibrated benchmark.

[manifest.json](manifest.json) freezes 24 examples, four each for public factual questions, explanation requests, past decisions, ordinary notes, negation and incomplete writing. Two per category are development; two per category are held-out. The partition and expected route/usefulness labels were written before the first evaluation call. No development run or tuning took place. The set is balanced for diagnosis; its rates are not estimates of natural meeting prevalence.

All [images](images) use the repository's Caveat font on clean white backgrounds. All 24 were visually inspected for complete, legible rendering. The 12 held-out recognized transcripts were manually compared to the intended text, including negation and acronyms. These examples lack natural pen variation, erasures, genuine illegibility and realistic scribbles. [COLLECTION.md](COLLECTION.md) specifies the subsequent human capture and scoring pass, including those missing cases. The samples use generic fictional technical vocabulary, not private meeting notes.

[inputs.sha256.json](inputs.sha256.json) records frozen manifest/image hashes. [heldout-results.json](heldout-results.json) contains raw transcripts, uncertainty, effective routes, confidence, per-stage timing, provider/prompt/runner hashes and usage. [metrics.json](metrics.json) contains reproducible aggregates. The runner invokes the production `recognise` then `route` functions. It never calls `answer`, generates citations or uses web search. Usage: 24 HTTP requests, 10,701 input tokens, 355 output tokens, zero web tool calls, zero failed samples. This is billable API activity, not the in-app 60-job limit or an iPad session.

## Held out measurements

Final-pin figures below are **code-derived proxies for the frozen coordinator**, not observed UI counts or human usefulness ratings. `none` and `recall` suppress the final pin in this commit; other routes retain it. A useful actionable pin requires both a useful region label and its correct route. An unfinished line is labelled quiet while the writer is still composing, even though `clarify` is the correct semantic route.

| Measure | Result | Interpretation |
| --- | --- | --- |
| Recognition exact after whitespace normalization | 12/12 | Line wrapping ignored; no other text corrections needed |
| Expected effective route | 9/12 (75%) | Three effective clarification routes differed from labels |
| Final pin count | 8/12 | Pin proxy after recognition/routing, viewport permitting |
| Unwanted final pins | 4/6 quiet regions (67%) | Agenda headings, explicit negation and both incomplete lines |
| Useful regions lacking a correct actionable pin | 3/6 (50%) | Two recall routes intentionally silent in this commit; one explanation routed to clarification |
| Correct actionable pins among all final pins | 3/8 (38%) | Label-based proxy, not a human usefulness score |
| Ordinary notes finally quiet | 1/2 | Agenda headings leave a clarification pin |
| Explicit negation finally quiet | 1/2 | “Do not answer” leaves a clarification pin |
| Incomplete writing finally quiet | 0/2 | Both clarification pins are premature under the composing label |

| Stage | Median seconds | Maximum seconds | n |
| --- | --- | --- | --- |
| Recognition | 1.75 | 3.21 | 12 |
| Routing | 0.09 | 0.26 | 12 |
| Recognition plus routing | 1.86 | 3.28 | 12 |
| Estimated last stroke to review, adding 1.8 seconds | 3.66 | 5.08 | 12 |

The last row adds the configured debounce to API timings; it excludes actual canvas capture, rendering, scheduling, queue wait, cooldown skips, UI paint and user review. It is not measured end-to-end iPad latency or time to a useful answer. No ≥80% human usefulness or useful answer within 10 seconds is established.

| Held out sample | Expected route | Actual effective route | Confidence | Final pin proxy | Estimated pause to review seconds |
| --- | --- | --- | --- | --- | --- |
| question-03 | web_research | web_research | 0.99 | yes | 4.22 |
| question-04 | web_research | web_research | 0.81 | yes | 3.91 |
| explanation-03 | quick_response | clarify | 0.70 | yes | 3.38 |
| explanation-04 | quick_response | quick_response | 0.90 | yes | 3.53 |
| past_decision-03 | recall | recall | 0.96 | no | 3.92 |
| past_decision-04 | recall | recall | 0.94 | no | 5.08 |
| ordinary-03 | none | clarify | 0.45 | yes | 3.39 |
| ordinary-04 | none | none | 0.93 | no | 3.53 |
| negation-03 | none | clarify | 0.64 | yes | 3.68 |
| negation-04 | none | none | 0.79 | no | 3.48 |
| incomplete-03 | clarify | clarify | 0.80 | yes | 3.64 |
| incomplete-04 | clarify | clarify | 0.75 | yes | 4.68 |

## Failures and interruption burden

- **Agenda headings:** `ordinary-03` contains question marks but explicitly identifies them as headings. Confidence 0.45 becomes `clarify`, leaving an unwanted pin. Punctuation alone did not lead to web research, but ordinary writing did not stay quiet.
- **Negation:** `negation-03` preserves “Do not answer” exactly. Confidence 0.64 becomes `clarify`, leaving an unwanted pin despite the explicit instruction to avoid assistance. It does not start an answer or research.
- **Complete explanation:** `explanation-03` is a legible complete stack/queue request. Confidence 0.70 becomes `clarify`, adding an avoidable review step. The runner stores the post-threshold route, so it cannot attribute this to the raw class choice versus confidence calibration.
- **Incomplete lines:** `incomplete-03/04` correctly route to `clarify` but still leave final pins during composition. A semantic route match does not guarantee acceptable proactivity.
- **Recall:** both held-out references route correctly to private-history recall. The evaluated commit suppresses their final pins, so it provides no actionable automatic recall suggestion. This is a documented limitation, not permission to search the public web.
- **Transient activity:** before the route is known, the coordinator publishes a region, busy state and “Reading handwriting…” title. The overlay can show the pin for every eligible visible crop, including ordinary notes later classified `none`. A controlled test reproduces that state and its eventual removal. The live pipeline median of 1.86 seconds indicates potential transient exposure; actual visibility/duration was not timed in the UI. “Ordinary writing stays quiet” is therefore not confirmed even for final silent routes.

No participant session was run. Dismissal effort, writing delay, attention shifts, unwanted openings, pins per minute and subjective distraction are **unmeasured**. There is no automatic inspector-opening call in the pause path, but this report does not claim a new UI observation. The 20-second cooldown bounds eligibility; it does not prove low interruption burden. Topic dismissal/mute suppress subsequent routing only after recognition, so a changed crop may still be uploaded for recognition and briefly expose activity.

## Control checks and version boundary

The frozen starting commit plus this evaluation's added checks passed **15 coordinator test functions** (two parameterized functions each exercise two cases) on iPad mini (A17 Pro), iOS 26.2 simulator, Xcode 26.2 (17C52). [control-checks.txt](control-checks.txt) preserves the result summary; [control-tests.swift.txt](control-tests.swift.txt) preserves the exact frozen test source. Tests use controlled providers and shortened delays; they verify logic, not physical debounce timing or live handwriting.

Verified: Off/Explicit modes do not schedule capture/uploads; 20-second default cooldown drops a second pause while explicit routing still runs; latest-only queue; stale queued source rejection; explicit preemption and ownership; cancelled provider cannot publish; duplicate dismissal; topic mute; silent final routes; default 1.8-second setting; automatic research route stops at review with a blank public question and zero answer calls. A blank public question cannot start research. Public research still requires a separately reviewed query. Unattended web investigation remains additional scope.

**Concurrent checkout warning:** unrelated local recall work changed production files while the initial test build was running. That first shared-checkout run failed the existing assertion that recall leaves no pin; [concurrent-checkout-failure.txt](concurrent-checkout-failure.txt) records it. The evaluation did not revert or tune that work. The passing run used a temporary `git archive` of the starting commit plus the added tests. The live diagnostic's provider hash matches that commit; pin metrics intentionally refer to its coordinator. Later recall builds need fresh pin/retrieval evaluation and must not inherit these baseline pin counts. No clean test result for the changing shared checkout is claimed.

## Tuning decision and remaining work

Keep the production prompt, 0.75 threshold, 1.8-second pause and 20-second cooldown unchanged for this evaluation. Twelve uniform synthetic crops do not justify tuning for real handwriting. Lowering the threshold may recover a complete explanation while making false prompts worse; raising it turns more cases into pin-producing clarification. Inspecting the held-out failures has now consumed this set for diagnosis: any changes motivated by these results require fresh held-out confirmation.

For the essential demo, select a region explicitly, inspect/correct transcription, review a separate public question, and request research. Keep Automatic off in the main script. It may be shown only as an explicitly labelled experimental opt-in after a successful hands-on rehearsal with the actual writer. The baseline evidence does not support a claim that ordinary writing remains quiet.

For BIL-29, collect 20–30 human handwritten regions, add genuine scribbles/erasures, and reserve unseen wording before tuning. Measure actual last-stroke-to-pin/result times and writing burden. Manually check every displayed verified claim against the opened supporting source. Citation support is **not evaluated** in this run: no claims or citations were generated. Likewise, a correct recall route is not memory top-three relevance; measure retrieval separately if implemented in the next frozen build. These remaining checks do not block the explicit-selection demo.

## Reproduce

From the repository root:

```sh
xcrun swiftc -module-cache-path /tmp/pause-swift-module-cache -parse-as-library \
  ScribbleScout/Models/*.swift scripts/EvaluatePause.swift -o /tmp/evaluate-pause
python3 scripts/summarize-pause-evaluation.py
```

`--prepare` is for a new versioned dataset only and refuses to replace the existing image directory. The stored PNGs are the frozen inputs. A billable replay with the existing local credential, no web search and a new output file is:

```sh
/tmp/evaluate-pause --run-heldout --output /tmp/pause-replay.json
```

It checks input hashes and refuses to overwrite results. Live outputs can vary; do not replace the original held-out record. The summarizer reads the original run and verifies denominators and hashes. To rerun controls against the baseline, export the recorded app commit into a temporary directory, replace its `ScribbleScoutTests/AssistanceCoordinatorTests.swift` with `control-tests.swift.txt`, then run `xcodebuild` for `ScribbleScoutTests/AssistanceCoordinatorTests` on an available iPad simulator. The exact tested test-file hash is in `versions.json`.
