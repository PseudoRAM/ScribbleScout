# Scribble Scout demo

The demonstration is a native iPad notebook, not a meeting recorder. Original ink stays local. Live recognition sends the selected crop and a whole-canvas context snapshot to OpenAI. Only the selected text is transcribed. Explicit public research uses a separate question that the user reviews before sending. Automatic mode can research the recognised selected text directly.

## Prepare

1. Build the `ScribbleScout` scheme with Xcode 26.2 or later and run on an iPad. The deployment target is iPadOS 18.
2. Create a fresh note. Use fictional technical content, not workplace notes or customer names.
3. A runtime key enables live OpenAI processing and Automatic assistance on launch. Without a key, add one in Settings; explicitly choose fictional offline examples only for the account-free demo. Offline examples demonstrate the interaction; they are not live web findings or handwriting accuracy measurements.
4. Keep the original source page available. The example content on the old checkout reference page is a design reference, not a verified Stripe capability claim.
5. Use explicit assistance for the essential demonstration. Automatic assistance is enabled with a runtime key; explain the whole-canvas context it sends and show Pause/Off controls. Clear stable explanations stream into a canvas card. Automatic can research the recognised selected question or search local notes; uncertain text waits for review. Explicit research retains separate public-question review.

## Two-minute story

| Time | Action | What it proves |
| --- | --- | --- |
| 0:00–0:20 | Write a specific technical question with Apple Pencil, then add another note. | Ink remains the primary interaction. |
| 0:20–0:45 | Lasso the question and tap Ask Scout; recognition starts immediately. Inspect the crop, whole-canvas context and transcript, then correct the text if needed. | The user can catch extraction mistakes before research. |
| 0:45–1:10 | Review a minimal public question with names and private context removed. Start research, close the inspector and continue writing. | Research stays asynchronous; public query review is separate from private context. |
| 1:10–1:30 | Scroll the canvas response to its final caveat, then tap Review. Read the finding and limitation; open a real supporting source. | Returned citations are inspectable. A URL alone does not prove a claim. |
| 1:30–1:50 | Use Insert on the canvas card, or choose placement in Review. Edit the labelled AI block, undo acceptance, then redo. | Generated text is separate from ink and retains its sources. |
| 1:50–2:00 | Reopen the note and show the block. Briefly demonstrate an ambiguous question or stale result. | Persistence and a visible trust boundary, not just an API response. |

Do not claim the flow is live when using offline examples. Say which provider ran, what was corrected and what remains uncertain. Recall is optional; omit it if it distracts from the essential loop.

## Failure rehearsal

Run these before recording the live demonstration. Keep the result bundle and record the device, app commit, provider/model and observed timings.

- Clear handwriting, technical acronym, negation, incomplete phrase, erasure and a small mixed diagram. Record transcription errors rather than silently fixing them in the reported result.
- Edit or delete the source while research is running. The obsolete result must not attach to new writing. Move an intact source and check its pin resolves to the new position.
- Tap Scout’s status and check the explanation and Off / Explicit only / Automatic controls. Scout watches handwriting and does not record audio.
- Write an ordinary note or incomplete phrase: Decisions must not open an automatic response card. A useful question may show an answer; clarification remains available through Review.
- At the largest text size, scroll to the final caveat in portrait and landscape, then insert from the card. Undo must remove the inserted block in one step.
- Request the same source twice, dismiss it and enable automatic assistance. Check duplicates and muted topics remain suppressed.
- Cancel a pending request, then explicitly retry. Cancellation ends local waiting; remote processing and billing may continue.
- Try an invalid key, offline network and rate-limited response. Drawing, local saves and existing notes must remain usable.
- Check an incomplete or citation-free research response is withheld. Manually compare every displayed research claim with its cited source.
- Insert, edit, undo, redo, background and relaunch. Confirm ink, text, block placement and evidence survive.

## Recording and fallback

Record a successful run on the actual iPad. A simulator recording is useful implementation evidence but does not validate Apple Pencil feel or real handwriting. If the network fails, switch explicitly to offline examples and state that live research did not run. Keep a successful earlier live recording as a separate fallback.

For simulator capture after installation:

```sh
xcrun simctl io booted recordVideo output/demo-simulator.mov
# Perform the demo; stop recording with Control-C.
```

Record organiser slot/submission requirements separately. Neither a simulator video nor an installed development build establishes an accepted submission, TestFlight distribution or App Store release.

## Scope

BIL-5–17 cover the essential demo, with BIL-18 providing the bounded pause enhancement and BIL-19 selected explanations/follow-ups. BIL-20–22 dated local Recall is implemented as optional demo scope. Hosted services, accounts, study telemetry, sync and request-circle gestures are not needed for this demonstration.

## Verification · 20 October 2026

- 26 Foundation-only tests pass in Debug and Release, including transcription parsing, safe source modes, structured synthesis/source IDs, usage accounting, cancellation, rate limits and timeout behavior.
- 32 iOS persistence/coordinator tests pass, including block recovery and undo/redo, source moves and repeated validation, stale queued captures, explicit priority, cancellation, dismissal suppression, follow-up references and offline stale examples.
- Simulator UI checks pass for continuous drawing/undo/pan, notebook navigation/large text, and fictional research → insert → one-step undo/redo → edit → reopen. These are separate from a live handwriting demonstration.
- A signed build installs and launches on the paired iPad mini (6th generation). Real Apple Pencil feel and the complete live handwriting flow have not been checked by a human in this implementation session.
- Live synthetic checks passed for routing, quick answers, cited research plus structured synthesis, and printed-image extraction. Detailed measurements and their limits are in the README.
- The local credential-launcher and secret-guard self-checks pass. No key is bundled or included in the recording fixtures.

Outstanding rehearsal: evaluate actual handwriting/acronyms/negation/diagrams, manually check source support for the chosen demo question, confirm organiser requirements, and record the complete live run on the actual iPad. Do not replace these checks with the simulator or printed-image results.


## Optional dated Recall · BIL-20–22

Three fictional canvases install once, without replacing existing notes: checkout proposal (6 October), checkout follow-up (13 October), and unrelated infrastructure review (15 October 2026). Each excerpt retains its meeting date, canvas and region bounds, revision, evidence kind and claim status.

1. From any canvas, open **Page options → Recall dated meetings**. The prepared question is “What did our previous meetings say about custom checkout for annual plans?” Local retrieval should return the proposal and follow-up among the first three matching meetings and exclude infrastructure. No API key is required.
2. Inspect the dated excerpts. The custom build is a **proposal**; support for trials, tax and discounts is an unverified **assumption**. The **settled decision** is to validate requirements before selecting an implementation, not to approve a custom build.
3. Filter sources by claim status or the latest matching meeting. Choose **Open source region** to inspect a navigable canvas with the exact cited bounds highlighted. **Return to Recall**, then **Done**, returns to the mounted original editor, preserving its selection and viewport. Missing or changed source records require a fresh search.
4. To compare with public evidence, enter a separate public question, for example “What payment flows support annual subscriptions?”, then choose **Add public web evidence**. Only that field is sent to the research provider, with no selected image, notebook titles or private excerpts appended. The result displays private meeting excerpts and public findings in separate labelled passages, retaining both kinds of evidence. Offline mode uses labelled synthetic web fixtures.

Recall currently indexes dated, spatially anchored typed meeting excerpts. It does not recognise a library of arbitrary handwriting. A topical overlap guard excludes semantically generic meeting matches; paraphrases with no shared topical words may need a more specific query. Text edits to a seeded meeting remove its old spatial anchors, so stale excerpts cannot be navigated as current evidence.

## Pause assistance evaluation on 20 October 2026

Use **Explicit only** for the essential demo. The [versioned held-out synthetic diagnostic](evaluations/pause-v1/REPORT.md) matched 9/12 expected routes and exposed unwanted clarification/activity pins on ordinary notes and negation. No prompts or thresholds were tuned. Real-handwriting accuracy and interruption burden remain unmeasured; the 24 fictional font-rendered examples are collection prompts, not human handwriting evidence. Those results describe the frozen baseline. The current branch keeps automatic clarification in a quiet Review control and can run research directly from recognised text; explicit research still requires a separately reviewed query. The baseline pin counts do not validate the current response UI.

Recall verification: 28 Foundation tests and 42 iPad model/coordinator tests pass in the shared workspace, including prepared-question ranking, metadata refresh without re-embedding, private-query isolation and persisted anchor invalidation. The simulator Recall navigation test passes; its screenshot was inspected for region alignment. Combined live web research was not exercised in this session.
