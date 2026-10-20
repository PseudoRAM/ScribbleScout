# Human handwriting collection and scoring

No human handwriting was supplied for pause-v1. The 24 PNGs are fictional Caveat font renderings. Use these writing prompts for a new human dataset; do not relabel the synthetic run as handwriting evidence.

Collect in the actual iPad app with the intended writer's permission. Use the 24 texts and categories in `manifest.json`, but include natural abbreviations, line breaks, corrections, struck-out wording, acronyms, trailing incomplete strokes and two realistic illegible/scribbled regions. Retain the intended transcript separately from the recognizer output. Fictional prompts cover only generic technical vocabulary; personal meeting examples need the writer's permission before sharing or processing.

Freeze the new dataset, ground truth, desired route and desired pin before running it. Keep the first two examples per category as development and the last two as held-out. Have a different person add genuinely unseen wording to the next held-out set: pause-v1 has now been inspected and must not be reused to claim an independent tuning improvement. Store capture hashes, crop bounds, drawing revision, writer alias, device/OS, app commit/build, model, prompt hash, threshold and consent scope. Never overwrite v1. Do not commit real notebook content or credentials by default.

For the essential rehearsal, write one ordinary note, one complete question, one negation and one incomplete line. Pause naturally, including one mid-sentence pause of at least 1.8 seconds. Then test dismissal, mute, a second change inside 20 seconds, queued edits, an explicit request during automatic work and source erasure before completion. Use Explicit only for the demo if these distract the writer.

Record one row per actual region or writing event, including skipped events:

| Field | Recording rule |
| --- | --- |
| Ground truth | Intended text, category, expected route, whether assistance is useful now and why |
| Recognition | Raw transcript, uncertainty, character/word errors, lost negation/acronyms |
| Routing | Actual route, confidence, endpoint fallback, exact route match |
| Display | Busy pin and final pin shown, inspector opened automatically, source still current |
| Relevance | Human rating of the displayed prompt; unwanted final prompts / regions labelled quiet; missed useful prompts / useful regions |
| Timing | Last stroke, recognition start/end, routing end, pin shown, explicit research start/result; include failures, cooldown skips and timeouts |
| Burden | Dismissals, unwanted openings, writing resumptions delayed, 1–5 distraction rating; unwanted pins per minute with session duration |
| Controls | Mode, cooldown, mute/dismiss state, explicit request priority, queued replacement, source invalidation outcome |
| Claims | Claim text, source URL, supporting source passage, supports/partial/unsupported, checker and date |

Public research remains a separate explicit step: inspect/correct the transcript, write and review a public question, then request research. No automatic public investigation is part of this evaluation. For every displayed verified claim, open its cited source and manually record whether the source supports the precise claim, dates and caveats. A valid URL alone is insufficient. Record failed support as a failure; do not silently omit it. No claims were generated in the synthetic routing run, so citation support is unmeasured there.

Measure memory top-three relevance only if local recall is part of the frozen evaluated build. Record expected source IDs, top three returned IDs, dates, stale evidence and whether an old proposal was mistaken for a decision. Do not infer retrieval relevance from a correct `recall` route.

The proposed ≥80% usefulness and useful result within 10 seconds are initial targets, not established performance. A review pin is not an answer. Report denominators, stage timing and failures; decide whether Automatic is acceptable from observed handwriting and interruption behavior. Tune on development data only. Any change chosen after reading pause-v1 held-out results requires a fresh held-out confirmation set.
