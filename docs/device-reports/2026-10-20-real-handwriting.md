# Physical iPad handwriting validation · 20 October 2026

Tickets: BIL-5 and BIL-9. Status: **IN PROGRESS — human sample results pending**.
Neither ticket's remaining real-device acceptance criteria are satisfied by setup alone.

## Build and device evidence

- Source: fetched merged `origin/main`, `dfc4b8f72c0481370de11de751ed8417987aec6b`; working tree clean at build. Includes PR #10 and Pencil activation PR #11.
- Report branch: `codex/real-handwriting-validation`.
- Xcode 26.2 (17C52); iPhoneOS SDK 26.2; deployment target 18.0.
- Physical iPad mini (6th generation), iPad14,1; iPadOS 26.5 (23F77); wired, paired, Developer Mode enabled.
- Debug scheme `ScribbleScout`, development signed; `xcodebuild` reported **BUILD SUCCEEDED**.
- App version 0.1.0 (1); installed executable SHA-256: `93480085161d45cd0d42193f904961e735826cbee3ba8155ba2d3258128210c4`.
- CoreDevice confirmed installation of `au.com.billabyte.ScribbleScout`; session-key launcher returned success. No credentials are included in this report.
- Ben confirmed readiness to supply actual handwriting/Pencil interaction. Successful launch does not establish recognition or Pencil quality.
- Recognition path: previewed selected PNG → OpenAI Responses, `gpt-6-luna`; transcript and uncertainty reviewed before routing. Live mode/consent must be confirmed by Ben before the first sample.
- Initial sandbox device discovery timed out and GitHub DNS failed. Retrying with host access succeeded; these were workstation setup failures, not observed app failures.

## Measurement procedure

Use a fresh fictional note, Explicit only, live provider and processing consent. For each sample: write with Pencil, select the region, inspect the crop for clipped text or unrelated ink, recognise, close the inspector and continue drawing outside the selected source. Reopen the pin; preserve the raw transcript and uncertainty before editing. Record corrected text and whether editing is usable. Do not route/research until the transcription result is recorded.

Settings shows cumulative **Total request time**, rounded to 0.1 s. Record before/after values with no intervening routing, research or automatic requests; their difference estimates this sample's HTTP recognition latency, not complete UI latency. Separately label stopwatch measurements from tapping Recognise to seeing the result. Never substitute the historical printed-image timing. Record failed attempts and retries as separate rows. No latency or accuracy target is claimed from pending samples.

Check Pencil start-of-stroke response, continuous strokes, palm contact, accidental marks, lasso boundaries, correction caret/keyboard behavior and continued drawing during each request. Keep that drawing outside the selection; separately test an intentional source edit during recognition to verify stale-result handling.

## Sample outcomes

Suggested prompts below are **instructions, not observed original handwriting**. Ben's exact wording is recorded separately. Every pending field means unmeasured, not pass or zero.

| ID | Category / suggested fictional prompt | Actual original wording | Raw recognised wording | Reported uncertainty | Corrected wording / edits | Recognition time and method | Crop / Pencil / palm / concurrent drawing / correction observations | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| S1 | Clear question: Why does a database index speed up reads? | Pending | Pending | Pending | Pending | Pending | Pending | Not run / awaiting Ben |
| S2 | Acronyms/products: Can PostgreSQL use a GIN index for JSONB over HTTP? | Pending | Pending | Pending | Pending | Pending | Pending | Not run |
| S3 | Negation: Do not cache failed API responses. | Pending | Pending | Pending | Pending | Pending | Pending | Not run |
| S4 | Incomplete phrase: Should we move the cache to… | Pending | Pending | Pending | Pending | Pending | Pending | Not run |
| S5 | Erasure/correction: write Redis; erase it with Pencil; replace with PostgreSQL in “Store sessions in PostgreSQL.” | Pending | Pending | Pending | Pending | Pending | Pending | Not run |
| S6 | Diagram: draw boxes Client → API → DB; add “Do not retry writes.” | Pending | Pending | Pending | Pending | Pending | Pending | Not run |

For S3 and S6 explicitly record whether “not” survives. For S4 check whether uncertainty or subsequent clarification handles incompleteness without inventing missing words. For S5 record what was erased and what remains visible. For S6 retain a description of the actual diagram and record invented or omitted labels/arrows separately from prose errors.

## Failures and regressions

### U1 · Automatic assistance is confusing / no visible response

Ben reported during the first attempted sample: “Im so confused, its not happening automatically so I toggled it to work automatically and then its still a multi step thing and im not getting any response?”

Observed by Ben: no useful response visible and an unexpectedly manual flow after enabling Automatic. Exact handwriting, settings/consent state, transcript, uncertainty and timings remain unreported. This is a usability failure report, not a completed recognition-accuracy test.

Inspection of the installed `dfc4b8f` source found: opening Scout without a selection prepares a typed manual region; `schedulePause` refuses automatic work while an explicit region exists; changing to Automatic does not schedule recognition until a drawing revision changes. Automatic recognition/routing also stops before answer generation and exposes a canvas pin rather than opening the inspector. These mechanisms can explain the report, but the actual on-device cause is not confirmed.

Diagnostic retry requested: dismiss the current suggestion, close the inspector, write a fresh question, pause approximately two seconds and inspect any Scout pin. No replacement build or code fix has been installed. Reproduction and on-device retry result pending.

For an observed failure record sample/attempt, exact action sequence, expected/actual behavior, reproducibility, fixed commit and targeted regression evidence where practical. Revalidate fixes on the physical iPad.

## Completion gate

- [x] Build/install/launch current merged main on paired iPad mini.
- [x] Ben available for actual handwriting interaction.
- [ ] Confirm live provider, model and processing consent during samples.
- [ ] Record all six real handwriting sample outcomes, errors, uncertainty, corrections and timings.
- [ ] Observe Pencil responsiveness, palm rejection, selection and correction usability.
- [ ] Verify drawing continues during recognition.
- [ ] Investigate reproducible failures, add practical regressions and retest fixes.
- [ ] Assess remaining BIL-5/BIL-9 device criteria using the recorded evidence; close only when satisfied.
