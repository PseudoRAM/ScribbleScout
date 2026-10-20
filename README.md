# Scribble Scout: AI Note Taking

A native, pen-first notebook for iPad, built with SwiftUI and PencilKit. Capture handwriting, sketches, and typed notes in a small local library.

**Current milestone: local notes, on-device semantic search, and explicit AI assistance.** Local search uses Apple’s available English sentence embeddings with text matching as a fallback. Ask Scout routes typed questions and lassoed canvas images through OpenAI Decisions to quick answers, cited web research, or a browser search. The live Swift API smoke check passed on 20 October 2026. Automatic handwriting recognition and pause-triggered assistance remain planned; reference-page cards still contain example content.

## What works today

- Create, rename, search, select, and reopen notes with titles and dates.
- Find notes by meaning and exact terms, with matching excerpts, using an on-device vector index.
- Ask Scout about typed text or a lassoed canvas region: get a quick answer, research with citations, or open a public question in the browser.
- Write with Apple Pencil, or enable finger drawing for the simulator and touch input.
- Use a pen, highlighter, stroke eraser, or lasso, with ink color and width controls.
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

In Xcode, choose the **ScribbleScout** scheme and an installed iPad simulator, then Run (⌘R). Local note-taking needs no credentials or backend. Optional Ask Scout assistance uses your own OpenAI API key supplied at launch in Debug or entered at runtime.

### Run on an iPad

1. Connect and unlock the iPad. Complete pairing and approve Trust if prompted.
2. Enable Developer Mode on the iPad if Xcode requests it.
3. Sign in to your Apple Account in **Xcode → Settings → Accounts**.
4. Under **ScribbleScout → Signing & Capabilities**, select your development team. The repository currently uses the BILLABYTE team; other developers should choose their own team and a bundle identifier they can sign.
5. Select the connected iPad as the run destination and Run (⌘R).

If signing fails with a rejected account login, sign in again in Xcode before retrying. Signing certificates and provisioning profiles are kept outside this repository.

## Secrets and local configuration

The notebook works without credentials. Ask Scout uses OpenAI; no database, sync, or other provider keys are needed yet. `.env.example` lists the one credential to prepare. The `gpt-6-luna` Decisions, Responses, and web-search paths passed a synthetic live check; image extraction and broader evaluation remain in [BIL-6](https://linear.app/billabyteau/issue/BIL-6/verify-live-openai-access-and-choose-supported-model-paths).

### What to prepare now

1. In the [OpenAI API platform](https://platform.openai.com/), create a separate development project for Scribble Scout, enable API billing if needed, and review its available spending controls and usage alerts. Check actual usage while testing.
2. Create a project API key with only the permissions needed for the demo. Keep the original in your password manager. Never paste it into this chat, Linear, screenshots, source code, or terminal commands/history.
3. Create a private `.env.local` from the template using the command below. Then open it in a text editor and put the key after `OPENAI_API_KEY=`. Only edit `.env.local`; leave `.env.example` empty. The command gives a new file owner-only permissions and preserves an existing file:

   ```sh
   (umask 077; cp -n .env.example .env.local)
   ```

4. `.env.local` is a plaintext local convenience for the Mac-side API check or a future backend. It is ignored by Git and is **not loaded by the current app**. Keep it outside the Xcode target and Copy Bundle Resources. For Debug runs, the local launcher below passes this key to the app process at launch. Otherwise, enter your own key in Ask Scout; it is never bundled.

### How this works in Swift

Swift/iOS does not automatically read `.env` files. Xcode scheme environment variables apply to launches from Xcode; they are not a deployment mechanism for an installed app. Copying a secret into Swift, `Info.plist`, resources, or build settings can expose it in the app or build artifacts. An ignored file protects against ordinary Git adds; it does not make a bundled value private.

The personal prototype ([BIL-10](https://linear.app/billabyteau/issue/BIL-10/implement-direct-openai-transport-and-user-owned-credential-controls)) accepts your own key in Ask Scout, or reads `OPENAI_API_KEY` from its process environment in Debug only. It keeps the active key in session memory and offers **Forget key**. Keychain persistence is not implemented. Keychain is encrypted storage for a user's credentials, not a way to hide a shared developer key shipped with the app. See [Apple's Keychain guidance](https://developer.apple.com/documentation/security/using-the-keychain-to-manage-user-secrets).

For the managed TestFlight/App Store edition, the shared OpenAI key belongs in the backend's secret store. The iPad app will authenticate to that backend with a user's session. [OpenAI's authentication documentation](https://developers.openai.com/api/reference/overview#authentication) says to keep API keys out of client-side code and load them on the server. A hosted backend and authentication are later work ([BIL-25](https://linear.app/billabyteau/issue/BIL-25/build-the-minimal-authenticated-hosted-assistance-backend)). Apple signing stays managed by Xcode; don't put Apple passwords, signing private keys, or certificates in `.env` or the repo.

### Local Debug key with manual fallback

The app reads `OPENAI_API_KEY` from its launch environment in Debug builds only. It never reads `.env.local` from the app bundle. If the variable is absent, blank, or malformed, Ask Scout shows the secure key field. Release builds ignore this variable and use manual entry. **Forget key** clears the active session credential and reveals the field; it does not edit the Mac's `.env.local`. Processing permission remains a separate opt-in.

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

There is no cloud sync or analytics. Ask Scout sends your question and, for a lasso request, the previewed canvas image to OpenAI after processing is enabled. Nearby context is included by default; the preview marks the selected focus, and you can switch context off. Other notebook content and local search results are not uploaded. Web research sends only a separately entered public question, without the canvas image. Storage recovery protects against an interrupted save; it is not an external backup. Uninstalling the app removes its local notes. Export, deletion, and multi-page notebooks are not part of this first version.

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
| `ScribbleScout/ScoutSheet.swift` | Explicit requests, session key, disclosure, cancellation, browser handoff |
| `scripts/CheckOpenAI.swift` | Synthetic live account smoke check using the ignored local key |
| `ScribbleScout/Notebook.swift` | Local snapshots, autosave sessions, and library state |
| `ScribbleScout/InkCanvas.swift` | PencilKit bridge, paper rendering, viewport, and ink controls |
| `ScribbleScout/NotebookView.swift` | Library, search, note editor, and drawing toolbar |
| `ScribbleScoutTests/NotebookTests.swift` | Persistence and recovery tests |

The starting content area is **1,000 × 1,400 points** (`NotebookPage.size`); the reference template is **1,448 × 1,026 points**. The scrollable canvas expands around these areas without moving existing ink coordinates. The paper grid renders only the visible region, and the minimap caches a small preview after ink settles. The implementation uses Apple's frameworks directly; no OwlLuna or other upstream application code was copied. Snapshot writes currently run synchronously and suit a small notebook; larger libraries may need background I/O.

## Ask Scout and the routing plan

Open the **sparkles** button in the drawing toolbar, or **Page options → Ask Scout**. If no development key was supplied, enter your own API key. Enable OpenAI processing, then type or paste a short question. Alternatively, choose **Lasso**, draw around handwriting, typed text, or a sketch, then tap **Ask AI** beside the selection. Check the image preview and edit the question before sending. **Use nearby canvas context** is on by default: the image includes a 300-point margin around the lasso, and a burgundy outline identifies the focus. Switch it off to send only the masked selection. The app observes the lasso region using public touch APIs alongside PencilKit, without private selection APIs or clipboard access. Moving/editing ink or switching tools clears the captured region. Lasso images are not saved into notes or uploaded automatically.

| Route | Behaviour |
| --- | --- |
| `quick_response` | Short Responses answer with no search tools. |
| `web_research` | Enter a public question, then choose cited in-app research or **Open in browser**. Private routing text is not forwarded to search. |
| `recall` | Direct you to the existing local notebook search; no public search. |
| `clarify` | Wait for more context. Also used below the provisional Decisions confidence threshold of 0.75. |
| `none` | Leave ordinary notes and requests to avoid assistance alone. |

`URLSession` transport uses HTTPS, timeouts, request IDs, cancellation, and explicit retry through the action buttons. Decisions uses `gpt-6-luna`; a 403/404 or unavailable-model error falls back to a strict structured Responses router with the same model. Missing model access can still fail in the fallback. Authentication, rate limits, malformed output, and network failures do not silently retry.

Responses calls use `store=false`; Decisions receives no undocumented storage flag. This is not Zero Data Retention. Research requires a completed search and returned HTTP(S) citation metadata. Sources are linked inline when annotation offsets are available and listed below. This validates provenance metadata, not claim support. Each research request allows at most three built-in tool calls. A local 20-job session cap counts routing and answers separately; a routing fallback may make two calls in one job. Token/cost reporting and held-out evaluation remain BIL-30/BIL-29 work.

The plan remains: verify actual API access (BIL-6), connect selected handwriting and revision-safe requests (BIL-5/7/9/12), validate evidence and canvas insertion (BIL-13–16), then add opt-in pause detection, cooldown, and mute (BIL-18). The explicit typed/selected-image flow implements parts of BIL-6/10/11/19; it does not complete those issues. Reference-page cards remain illustrative.

Official contracts checked 20 October 2026: [Decisions](https://developers.openai.com/api/docs/guides/decisions) (public beta), [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs), [web search](https://developers.openai.com/api/docs/guides/tools-web-search), and [GPT-6 Luna](https://developers.openai.com/api/docs/models/gpt-6-luna).

Run the live smoke check from the repository root (three synthetic operations, billable to your API project):

```sh
xcrun swiftc -parse-as-library ScribbleScout/Models/OpenAIAssistance.swift \
  scripts/CheckOpenAI.swift -o /tmp/scribble-scout-check-openai
/tmp/scribble-scout-check-openai
```

The check reads `OPENAI_API_KEY` from the environment or `.env.local` without evaluating shell code. It prints routing latency, answer length, and public source titles/URLs; never the key or raw API error bodies. The Swift check passed on 20 October 2026: Decisions selected `quick_response` in 1.38 seconds without fallback, a quick answer returned, and web research returned a citation to the official Decisions documentation. Earlier restricted requests failed before authentication; the successful check ran with network access. The synthetic selected-image check (`--image`) also passed: Decisions chose a quick response and Responses read an arithmetic image correctly. Handwriting accuracy still needs real-device evaluation. Six additional synthetic routing examples also passed: quick answer, current web question, private recall, ambiguity, ordinary notes, and explicit no-research instructions. This is a smoke test, not a held-out accuracy estimate. Run `/tmp/scribble-scout-check-openai --routes` to repeat them.

## Next milestones

The roadmap is tracked in [AI Notebook: Pen to Evidence](https://linear.app/billabyteau/project/ai-notebook-pen-to-evidence-b701e6ca633c):

- [BIL-8: Local notebook foundation](https://linear.app/billabyteau/issue/BIL-8/build-the-swiftuipencilkit-workspace-with-durable-local-notes) — implemented and tested.
- [BIL-5: Device and recognition feasibility](https://linear.app/billabyteau/issue/BIL-5/verify-the-real-ipad-sdk-and-handwriting-recognition-path) — device deployment verified; recognition evaluation remains.
- [BIL-7: Shared assistance records and fixtures](https://linear.app/billabyteau/issue/BIL-7/define-shared-notebook-records-and-deterministic-provider-fixtures), followed by selected-handwriting recognition, cited research, and anchored evidence.

Audio, calendar integration, spatial handwriting recall, sync, and hosted services are outside this initial milestone. Local text recall is now available through notebook search; the reference page’s assistance cards remain static examples. A project licence has not been selected yet; that decision and the full open-source release checklist remain in [BIL-24](https://linear.app/billabyteau/issue/BIL-24/prepare-a-reproducible-credential-free-open-source-release).
