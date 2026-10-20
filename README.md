# Scribble Scout: AI Note Taking

A native, pen-first notebook for iPad, built with SwiftUI and PencilKit. Capture handwriting, sketches, and typed notes in a small local library.

**Current milestone: a complete explicit pen-to-evidence implementation.** Lasso a region, inspect and correct its transcription, review a separate public question, run cited research, and insert an editable AI block with preserved sources and undo. Source changes invalidate pending results; intact translated ink can retain its anchor. A runtime API key enables live processing and Automatic mode; fictional offline mode is an explicit option. After a pause, Decisions routes changed handwriting to a quick answer, web research, local Recall or no assistance. Automatic research uses the recognised question; explicit research uses a separately reviewed public question. Real handwriting accuracy and the full live-iPad demo remain hands-on validation tasks. See [the demo script](docs/DEMO.md) and [recognition/toolchain notes](docs/RECOGNITION.md).

## What works today

- Create, rename, search, select, and reopen notes with titles and dates.
- Find notes by meaning and exact terms, with matching excerpts, using an on-device vector index.
- Inspect and correct selected handwriting transcription, then ask for a quick answer or explicitly review a public research question.
- Inspect real web sources and caveats, then insert, edit, move, delete, undo and reopen labelled AI blocks without rewriting ink.
- Continue drawing while research runs; source pins show progress and stale results are withheld.
- Rehearse with clearly labelled fictional offline scenarios, or use live OpenAI with session credentials, consent and measured usage.
- Recognise and route changed handwriting after a pause, with topic dismissal/mute and a cooldown. Automatic mode can start public research using recognised text; ordinary notes and clarification decisions do not open a response card.
- Tap Scout’s status for an explanation and mode controls. Scroll the full canvas response and insert an editable AI block directly, or open Review for evidence and placement options.
- Write with Apple Pencil, or enable finger drawing for the simulator and touch input.
- Use a pen, highlighter, stroke eraser, or lasso, with ink color and width controls.
- Choose Select to circle and move ink or shapes, or drag AI blocks directly; movement supports undo and saves automatically. Select accepts touch even when finger drawing is off. Photos and printed page content remain fixed.
- Undo and redo ink edits; pinch to zoom, explore an expanding canvas in any direction, and return to the start.
- Navigate with a collapsible minimap showing your notes and the current visible area.
- Choose dotted, ruled, or blank paper and keep typed notes alongside each canvas.
- Save automatically, restore the last open note, and retain each note's zoom and scroll position.
- Recover the previous complete snapshot if the latest metadata or ink is unreadable. A failed save keeps the edited note open and offers Retry.

## App icon

<img src="docs/app-icon/preview.png" alt="Scribble Scout icon: two burgundy S-like ink strokes on warm ivory paper with a folded corner" width="160">

The paper fills the icon background; there is no green surround. The native [Icon Composer document](ScribbleScout/AppIcon.icon) contains three 1024 × 1024 PNG assets: the paper and folded corner, the transparent upper scribble, and the transparent lower scribble. Both ink marks remain separate editable layers.

Open `ScribbleScout/AppIcon.icon` in Icon Composer (included with Xcode 26.2) to adjust the layers. The app target uses `AppIcon` in Debug and Release; Xcode compiles the layered icon for iOS/iPadOS 26 and generates compatibility icons for earlier supported systems. The system applies the outer icon mask. Keep the source layers square, preserve ink transparency, and keep the paper opaque. Glass and translucency are disabled for the ink to preserve the burgundy color.

The artwork was separated from the selected concept using built-in imagegen, then normalized to 1024 pixels with `sips`. The upper stroke is positioned 50 points higher in Icon Composer to keep space between the marks. [Generation prompts](docs/app-icon/prompts.txt) are saved with the source assets. For Apple's workflow, see [Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer).

To regenerate the README preview on a Mac with Xcode installed:

```sh
"/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \
  ScribbleScout/AppIcon.icon --export-image --output-file docs/app-icon/preview.png \
  --platform iOS --rendition Default --width 1024 --height 1024 --scale 1
```

## Requirements

| Requirement | Supported / verified |
| --- | --- |
| Development tools | Xcode 26.2; no third-party packages |
| Minimum deployment target | iOS / iPadOS 18.0 |
| Primary platform | iPad; iPhone layouts are also enabled |
| Simulator verified | iPad Pro 13-inch (M5), iPadOS 26.2 |
| Physical device verified | iPad mini (6th generation), iPadOS 26.5: signed build, installation, launch, and running-process check |

Apple Pencil feel, palm rejection, and the full handwriting workflow on the physical iPad still need a hands-on check. Simulator checks cover creating and switching notes, typed text, search, paper rendering, ink undo/redo, and reopening saved content after relaunch.

## Get started

```sh
git clone https://github.com/PseudoRAM/ScribbleScout.git
cd ScribbleScout
open ScribbleScout.xcodeproj
```

In Xcode, choose the **ScribbleScout** scheme and an installed iPad simulator, then Run (⌘R). Local notes and fictional offline assistance need no credentials or backend. For live assistance, open Ask Scout → Settings, turn off Fictional offline demo, provide your own OpenAI API key and enable processing. Debug launches can supply your local key without bundling it.

### Run on an iPad

1. Connect and unlock the iPad. Complete pairing and approve Trust if prompted.
2. Enable Developer Mode on the iPad if Xcode requests it.
3. Sign in to your Apple Account in **Xcode → Settings → Accounts**.
4. Under **ScribbleScout → Signing & Capabilities**, select your development team. The repository currently uses the BILLABYTE team; other developers should choose their own team and a bundle identifier they can sign.
5. Select the connected iPad as the run destination and Run (⌘R).

If signing fails with a rejected account login, sign in again in Xcode before retrying. Signing certificates and provisioning profiles are kept outside this repository.

## Secrets and local configuration

The notebook and fictional offline assistance work without credentials. Live Ask Scout uses OpenAI; no database, sync, or other provider keys are needed. `.env.example` lists the one credential to prepare. The `gpt-6-luna` Decisions, Responses transcription, web-search and structured-synthesis paths passed synthetic live checks on 20 October 2026. Real handwriting evaluation remains separate from these API checks.

### What to prepare now

1. In the [OpenAI API platform](https://platform.openai.com/), create a separate development project for Scribble Scout, enable API billing if needed, and review its available spending controls and usage alerts. Check actual usage while testing.
2. Create a project API key with only the permissions needed for the demo. Keep the original in your password manager. Never paste it into this chat, Linear, screenshots, source code, or terminal commands/history.
3. Create a private `.env.local` from the template using the command below. Then open it in a text editor and put the key after `OPENAI_API_KEY=`. Only edit `.env.local`; leave `.env.example` empty. The command gives a new file owner-only permissions and preserves an existing file:

   ```sh
   (umask 077; cp -n .env.example .env.local)
   ```

4. `.env.local` is a plaintext local convenience for the Mac-side API check or a future backend. It is ignored by Git and is **not loaded by the current app**. Keep it outside the Xcode target and Copy Bundle Resources. For Debug runs, the local launcher below passes this key to the app process at launch. Otherwise, open Ask Scout → Settings, turn off Fictional offline demo, and enter your own key; it is never bundled.

### How this works in Swift

Swift/iOS does not automatically read `.env` files. Xcode scheme environment variables apply to launches from Xcode; they are not a deployment mechanism for an installed app. Copying a secret into Swift, `Info.plist`, resources, or build settings can expose it in the app or build artifacts. An ignored file protects against ordinary Git adds; it does not make a bundled value private.

The personal prototype ([BIL-10](https://linear.app/billabyteau/issue/BIL-10/implement-direct-openai-transport-and-user-owned-credential-controls)) accepts your own key in Ask Scout, or reads `OPENAI_API_KEY` from its process environment in Debug only. It keeps the active key in session memory and offers **Forget key**. Keychain persistence is not implemented. Keychain is encrypted storage for a user's credentials, not a way to hide a shared developer key shipped with the app. See [Apple's Keychain guidance](https://developer.apple.com/documentation/security/using-the-keychain-to-manage-user-secrets).

For the managed TestFlight/App Store edition, the shared OpenAI key belongs in the backend's secret store. The iPad app will authenticate to that backend with a user's session. [OpenAI's authentication documentation](https://developers.openai.com/api/reference/overview#authentication) says to keep API keys out of client-side code and load them on the server. A hosted backend and authentication are later work ([BIL-25](https://linear.app/billabyteau/issue/BIL-25/build-the-minimal-authenticated-hosted-assistance-backend)). Apple signing stays managed by Xcode; don't put Apple passwords, signing private keys, or certificates in `.env` or the repo.

### Local Debug key with manual fallback

The app reads `OPENAI_API_KEY` from its launch environment in Debug builds only. It never reads `.env.local` from the app bundle. If the variable is absent, blank, or malformed, live-mode settings show the secure key field. Release builds ignore this variable and use manual entry. **Forget key** clears the active session credential and reveals the field; it does not edit the Mac's `.env.local`. Processing permission remains a separate opt-in.

After installing a current Debug build locally, launch it on the connected iPad with:

```sh
xcrun devicectl list devices
python3 scripts/LaunchWithLocalKey.py --device <device-identifier>
```

For an already-installed simulator Debug build:

```sh
python3 scripts/LaunchWithLocalKey.py --simulator booted
```

The launcher prefers the Mac's `OPENAI_API_KEY`, then reads the ignored `.env.local`. With neither, the app requests a key. It passes credentials using Apple's child-process environment mechanism, never command arguments, a shared scheme, build settings, generated files, or resources. It parses only the key assignment without executing the file. The launcher only opens an installed app: it does not build, install, archive, commit, push, upload, or publish anything. A launch-supplied key lasts for that process; ordinary Home Screen launches fall back to manual entry. Use this only for personal development; the managed edition still requires server-held provider credentials.

Run `python3 scripts/test-local-key-launcher.py` for synthetic checks of precedence, absent credentials, safe parsing, and secret-free arguments. `swift test` and `swift test -c release` verify the Debug/Release credential boundary.

### Keep credentials out of commits

`.gitignore` excludes local env files, `secrets/`, `Secrets.plist`, `Secrets.xcconfig`, `*.local.xcconfig`, and signing/private-key files. Only `.env.example` is allowed, with empty values. Build folders, `.app`, `.ipa`, `.xcarchive`, and `.dSYM` artifacts are ignored and rejected by the commit guard even if force-added. The Python 3 pre-commit check also rejects local credentials, likely OpenAI keys, and PEM private-key headers in staged files. A pre-push check scans outgoing commit history, including content deleted from the final snapshot. It reports filenames/reasons without printing matched values.

Enable the check once per clone:

```sh
chmod +x .githooks/pre-commit .githooks/pre-push
git config --local core.hooksPath .githooks
```

Before committing, verify:

```sh
git check-ignore .env.local     # should print .env.local
git ls-files '.env*'           # should list only .env.example once committed
python3 .githooks/pre-commit   # checks the staged snapshot; silent means pass
git diff --cached --stat
```

The hooks check common mistakes, not every possible secret, and can be bypassed. Review staged changes locally too. If a real key is ever committed or shared, revoke/rotate it immediately; deleting the file or adding it to `.gitignore` does not remove it from Git history. Run `python3 .githooks/test-secret-guard.py` for an isolated check of the guard.

## Using the notebook

Open **Your notebook** using the grid button to browse notes on a full page. Search, sort by edit date or title, and tap a card to open it. Use a card’s trash button to delete one note, or **Select** to choose several, then **Delete**. Deletion requires confirmation and permanently removes the selected notes and their contents; it cannot be undone. Sample notes are installed once and stay deleted after relaunch. **Back to note** returns to the open canvas.

Create a note with **New note** and edit its title at the top. Switch between **Handwriting** and **Text** to add ink or typed notes to the same record. Search combines exact terms with semantic matches in titles and typed text, plus the built-in reference page transcript. Results show the best matching excerpt and open the source note. It does not recognise handwriting or text inside photos yet. The search status identifies on-device English semantic search or text-only fallback. Other languages can still match text, but semantic results use the English model.

In Handwriting mode, the toolbar provides the drawing tools, color, and width. **Page options** (the ellipsis button) changes paper and toggles finger drawing.

| Input mode | Write | Scroll / zoom |
| --- | --- | --- |
| Default | Apple Pencil | One finger to scroll; pinch to zoom |
| Draw with finger | Finger or Apple Pencil | Two fingers to scroll; pinch to zoom |

Keyboard shortcuts: **⌘N** creates a note, **⌘Z** undoes ink, and **⇧⌘Z** redoes ink. Ink undo history belongs to the open canvas and is not saved across app launches.

The canvas grows as you pan beyond its edges, including left and above the starting area. The minimap starts collapsed; tap the small map button to open it. Tap or drag the minimap to jump to another area; its outlined rectangle shows your current view. The house button returns to the starting area at fit width, and the chevron collapses the map. Sharing includes ink beyond the starting page and limits the exported image to 4,096 pixels on its longest edge.

## Local storage and recovery

Notes live in the app's `Application Support/ScribbleScout` directory, with one UUID folder per note:

```text
<note-id>/
  note.json         # Current metadata, typed text, viewport, and ink filename
  previous.json     # Previous complete metadata snapshot
  <uuid>.drawing    # Original PencilKit ink, stored separately
```

Ink changes write an immutable drawing file first. The app then atomically commits metadata pointing to that file, retaining the previous complete snapshot. Obsolete ink is removed only after the commit, keeping files referenced by either snapshot. Autosave runs after a 350 ms pause; switching notes and backgrounding flush pending edits immediately.

A disposable `search-index.json` beside the note folders stores searchable excerpts, vectors, and the embedding model revision and dimensions. Apple’s [Natural Language sentence embeddings](https://developer.apple.com/documentation/naturallanguage/nlembedding) run locally on a serial background actor. Text is split at paragraph boundaries into windows of up to 400 characters; a linear cosine scan ranks matches alongside exact terms. A minimum cosine similarity of 0.4 filters semantic candidates; this is an initial heuristic, not a calibrated confidence score.

Search updates after a short pause, including unsaved title/text edits. Unchanged searchable text reuses its vectors; dates, scrolling, paper changes, and ink-only edits do not re-embed text. Model revision/dimension changes rebuild the cache. Searches use only the current notebook records and reject stale text; records absent from that notebook are removed from the next cache update. A missing or unreadable cache rebuilds from the notes. Cache write failures leave search usable in memory and show a status message; they never prevent note saves. No cloud fallback or model download is requested. If the English model is unavailable, search uses text matching; relaunch after system model availability changes.

There is no cloud sync or analytics. After processing is enabled, tapping Ask Scout on a lasso selection immediately transcribes the selected crop using a second whole-canvas snapshot as context. Both images appear in the inspector. Routing and quick answers use the corrected text and the canvas snapshot, including offscreen content. Images are scaled down on large canvases. Local search results are not appended to public research. Automatic web research uses the recognised selected text as its question; explicit research uses a separately reviewed public question. Canvas images are excluded from web research. Storage recovery protects against an interrupted save; it is not an external backup. Uninstalling the app removes its local notes. Page image sharing includes accepted AI blocks. AI blocks and entire notes can be deleted. Multi-page notebooks are not part of this version.

## Tests

Unit and persistence tests use Apple's [Swift Testing](https://developer.apple.com/documentation/testing) framework, included with Xcode. Use `@Test`, `#expect`, and `#require` for new tests; use XCTest / XCUIAutomation when adding UI or performance tests. No third-party testing packages are needed.

For fast logic tests, run from the repository root:

```sh
swift test
```

This tests the app's actual Foundation-only note models through Swift Package Manager. It checks metadata round trips for every paper style, compatibility with existing notes that omit an ink filename, and rejection of damaged metadata. It also verifies local cosine ranking with three fictional notes, exact-term fallback, cache round trips, text/model invalidation, removal of absent records, invalid vectors, and Unicode chunking. It also checks routing confidence, endpoint fallback, credential errors, selected-image input, exclusion of images from public research, research tool policy, completed-search requirements, and source links using mocked transport. No app, simulator, signing, or network access is needed. The first run compiles the package; subsequent runs reuse the build.

For PencilKit persistence, recovery, and autosave tests, run **Product → Test** (⌘U) in Xcode, or use an installed simulator:

```sh
xcodebuild -project ScribbleScout.xcodeproj -scheme ScribbleScout \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO test
```

Choose a simulator available on your Mac if that model is not installed. The suite uses real PencilKit strokes and a separate temporary storage directory per test, so tests can run in parallel without sharing saved notes. It covers:

- Ink, text, paper, and viewport round trips, with separate notes kept isolated.
- Recovery from damaged metadata and an interrupted ink write.
- Recovery from a corrupt latest drawing.
- Retention of only the current and previous drawing snapshots.
- Preservation of in-memory edits when saving fails, and successful retry after storage becomes available.
- All paper styles, legacy metadata, reference-page attachments, and rectangle insertion.
- Negative-coordinate rendering, viewport restoration, source fingerprints, and bounded exports. Canvas UI tests draw in all four directions and check undo/redo and relaunch persistence.
- Lasso crop masking, neighbouring context, bounded image size, and preservation of ink and clipboard state.
- On-device search cache persistence/reload, corrupt-cache recovery, unchanged-cache reuse, and native model availability/fallback.
- Recovery from missing drawings, mismatched note IDs, and invalid drawing paths.
- Library ordering and warnings while preserving unreadable files.
- Autosave of the latest text and ink; viewport saves preserve the edit date and reuse ink.

Tests run locally; there is no automatic cloud test workflow. For local simulator coverage, add `-enableCodeCoverage YES -resultBundlePath build/Testing.xcresult` to the `xcodebuild` command above; remove the previous result bundle before reusing that path.

For a hands-on device check: create two notes, write and erase ink, undo/redo, zoom and scroll, switch notes, then background and relaunch. Confirm that the ink, typed text, and viewport survive.

## Code layout

| File | Responsibility |
| --- | --- |
| `ScribbleScout/ScribbleScoutApp.swift` | App entry point and lifecycle save |
| `ScribbleScout/Models/NoteRecord.swift` | Foundation-only note metadata shared with the fast unit test package |
| `ScribbleScout/Models/NoteSearchIndex.swift` | Search chunks, disposable vector cache, cosine ranking, and exact terms |
| `ScribbleScout/LocalSemanticSearch.swift` | Serial on-device Apple model inference and cache I/O |
| `ScribbleScout/Models/OpenAIAssistance.swift` | Decisions routing, Responses fallback, answers, and cited web search |
| `ScribbleScout/ScoutSheet.swift` | Transcription review, evidence inspector, credentials, modes and disclosure |
| `ScribbleScout/AssistanceCoordinator.swift` | Request lifecycle, source validation, bounded pause assistance and topic suppression |
| `ScribbleScout/AssistanceCanvasOverlay.swift` | Source pins, labelled blocks and block editing |
| `ScribbleScout/Models/AssistanceRecords.swift` | Durable regions, requests, evidence, blocks, provider contract and usage ledger |
| `ScribbleScout/Models/FixtureProvider.swift` | Clearly labelled account-free fictional scenarios |
| `scripts/CheckOpenAI.swift` | Synthetic live account smoke check using the ignored local key |
| `ScribbleScout/Notebook.swift` | Local snapshots, autosave sessions, and library state |
| `ScribbleScout/InkCanvas.swift` | PencilKit bridge, paper rendering, viewport, and ink controls |
| `ScribbleScout/NotebookView.swift` | Library, search, note editor, and drawing toolbar |
| `ScribbleScoutTests/NotebookTests.swift` | Persistence and recovery tests |

The starting content area is **1,000 × 1,400 points** (`NotebookPage.size`); the reference template is **1,448 × 1,026 points**. The scrollable canvas expands around these areas. PencilKit uses a fixed positive backing origin so fresh handwriting works left and above the starting page; saved ink, viewports, lasso regions, exports and Scout sources retain page coordinates. The backing reserves 65,536 points left/up; navigation stops at that boundary, while right/down extents grow. Keeping the backing origin stable preserves native ink undo history. The paper grid renders only the visible region, and the minimap caches a small preview after ink settles. The implementation uses Apple's frameworks directly; no OwlLuna or other upstream application code was copied. Snapshot writes currently run synchronously and suit a small notebook; larger libraries may need background I/O.

## Ask Scout and the demo loop

Open the sparkles button to type a question, or choose Lasso, surround handwriting or printed canvas content, and tap Ask Scout. With a runtime key, Scout starts in live **Automatic** mode. Without one, the status offers Settings to add a key or explicitly enable **Fictional offline demo**: examples are local, scripted and explicitly labelled. Settings offers grounded, ambiguous, failed, stale and conflicting-source examples. These are interaction fixtures, not live findings or recognition benchmarks.

For a live selection, turn off offline mode in Settings, enter your own key if needed, and enable OpenAI processing. The crop preview is exactly the selected area sent for recognition. Lasso → Ask Scout starts recognition immediately. Inspect uncertain tokens and correct the editable transcript before **Use corrected text** in Explicit only mode. A quick-answer route offers an explicit answer action. A research route asks you to enter a minimal **Public research question** separately: remove names, private decisions and confidential content. The canvas image is not forwarded to public search. In Automatic mode, a web-research decision uses the recognized text directly as the search question.

Research runs while the inspector is closed and shows a scrollable response card near its source. Its Insert action places an editable block below the writing; Review opens the inspector with source titles/domains, retrieval time and placement options. Open a supporting URL before trusting a claim. Insertion avoids occupied ink/blocks. The separate labelled block can be edited, moved, deleted and undone using the canvas undo manager. Its original source, evidence and acceptance/edit timestamps persist in note metadata. Existing ink is unchanged. Switching notes cancels unfinished assistance; accepted blocks remain saved.

Every source carries app-owned identity, bounds and a content fingerprint. Before displaying or inserting, the coordinator revalidates it. Unrelated ink can leave the source valid; an intact, uniquely identifiable translation can rebase the pin. Changed, erased, deleted or ambiguous source matches become stale. Original source bounds are retained to prevent repeated-validation drift. Source identity uses public drawing data, not stroke-array positions or unavailable OS 27 APIs.

| Route | Behaviour |
| --- | --- |
| quick_response | Concise answer with no search tools; starts automatically in Automatic mode. |
| web_research | Automatic mode researches recognized text; explicit mode uses a separately reviewed public question. Both use bounded cited research. |
| recall | Automatically retrieve dated local meeting excerpts in Automatic mode with claim labels and navigable source regions; optionally add separately reviewed public research. |
| clarify | Automatic mode keeps a quiet Review control; inspect uncertain text or add missing context before continuing. |
| none | Leave ordinary notes alone. |

Settings offers Off, Explicit only and Automatic. A runtime key enables Automatic by default. Automatic waits 1.8 seconds after an ink change, captures a bounded changed region and recognises/routes it through Decisions. Only an actionable route opens a response card; ordinary notes and clarification remain quiet. Tap the status to learn what is processed and change modes. No audio is recorded. Clear text automatically starts the chosen quick answer, web research or local recall without opening the inspector. Automatic web research uses the recognized text as its query; explicit research still requires a separately reviewed public question. Uncertain handwriting waits for review. The top-right spinner is muted during recognition/routing and burgundy during an action; a section spinner accompanies content in the source-anchored response card. A 20-second cooldown, one active job, a latest-only automatic queue, explicit-request priority, normalized dismissed topics and five-minute mute limit repetition. This is bounded in-app assistance, not indefinite background execution. Recognition still sends the crop to OpenAI in live automatic mode; processing consent is required.

The transport uses HTTPS, request IDs, timeouts, cancellation and explicit retry. Decisions uses gpt-6-luna; unavailable endpoint/model/access responses can fall back to a strict structured Responses router with the same model. This does not solve unavailable model access. Public research allows at most three built-in search calls, then uses a tool-free structured synthesis call whose source IDs must match actual returned citations. Code validates required fields, safe URLs, a short answer and a caveat; it does not establish that every source entails every claim. Inspect the sources.

Responses uses store=false; Decisions receives no undocumented storage flag. This is not Zero Data Retention. Session credentials are never persisted. A 60-stage session cap is a local convenience control, not an enforceable hosted quota. The usage ledger counts HTTP requests (including fallback, synthesis and failures), returned input/output tokens, tool calls and latency. Missing token reports are shown as partial totals; fictional fixtures do not count as billable usage. No dollar estimate is claimed.

### Reproduce API checks

These operations are billable to your API project. They read the ignored local credential without executing dotenv content and print only synthetic results/public source metadata:

```sh
xcrun swiftc -parse-as-library ScribbleScout/Models/*.swift \
  scripts/CheckOpenAI.swift -o /tmp/scribble-scout-check-openai
/tmp/scribble-scout-check-openai
/tmp/scribble-scout-check-openai --recognition
/tmp/scribble-scout-check-openai --routes
```

On 20 October 2026, the integrated pipeline returned a Decisions quick_response in 1.24 seconds, a quick answer and a cited result from the official Decisions documentation through retrieval plus structured synthesis. Four requests reported 9,508 input tokens, 265 output tokens and one search tool call. A separate generated printed-arithmetic image was transcribed correctly in 2.67 seconds (426 input/25 output tokens, no reported uncertainty). These are small synthetic smoke checks, not handwriting or end-to-end meeting benchmarks. The first arithmetic check exposed an overly narrow handwriting-only instruction; the prompt now correctly transcribes both handwritten and printed canvas text.

See [DEMO.md](docs/DEMO.md) for the two-minute script, recording/fallback instructions and physical-device failure checklist. Reference-page concept cards are opt-in and labelled fictional; they do not represent live research.

## Next milestones

The roadmap is tracked in [AI Notebook: Pen to Evidence](https://linear.app/billabyteau/project/ai-notebook-pen-to-evidence-b701e6ca633c):

- [BIL-8: Local notebook foundation](https://linear.app/billabyteau/issue/BIL-8/build-the-swiftuipencilkit-workspace-with-durable-local-notes) — implemented and tested.
- [BIL-5: Device and recognition feasibility](https://linear.app/billabyteau/issue/BIL-5/verify-the-real-ipad-sdk-and-handwriting-recognition-path) — device deployment verified; recognition evaluation remains.
- [BIL-7: Shared assistance records and fixtures](https://linear.app/billabyteau/issue/BIL-7/define-shared-notebook-records-and-deterministic-provider-fixtures) now underpin reviewed recognition, cited research, anchored pins and persisted blocks. See [the demo checklist](docs/DEMO.md) for the remaining physical-device validation.

Audio, calendar integration, spatial handwriting recall, sync, and hosted services are outside this initial milestone. Local text search and dated, spatially anchored fictional meeting Recall are available; see the optional Recall rehearsal in [docs/DEMO.md](docs/DEMO.md). Arbitrary handwriting-library recall remains outside scope. The reference page’s assistance cards remain opt-in static examples. A project licence has not been selected yet; that decision and the full open-source release checklist remain in [BIL-24](https://linear.app/billabyteau/issue/BIL-24/prepare-a-reproducible-credential-free-open-source-release).

### Automatic canvas responses

With a runtime API key, OpenAI processing and Automatic mode start enabled. Fictional offline examples are an explicit fallback (`--offline-demo` for deterministic UI rehearsal). After a writing pause, Scout reads the changed ink with whole-canvas context. Decisions chooses whether help is needed before a floating response card opens. Its text scrolls independently of the always-available Insert and Review actions. Stop or pause assistance from the visible controls. Uncertain handwriting requires review. Automatic can follow through to a quick explanation, local recall or web research using the recognised selected text; explicit research retains separate public-question review. Quick explanations use real network text deltas; citation-backed research appears after validation. No key is persisted.
