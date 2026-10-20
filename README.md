# Scribble Scout: AI Note Taking

A native, pen-first notebook for iPad, built with SwiftUI and PencilKit. Capture handwriting, sketches, and typed notes in a small local library.

**Current milestone: the local notebook foundation.** AI recognition and research are planned; they are not implemented yet. The app works offline and makes no network requests.

## What works today

- Create, rename, search, select, and reopen notes with titles and dates.
- Write with Apple Pencil, or enable finger drawing for the simulator and touch input.
- Use a pen, highlighter, stroke eraser, or lasso, with ink color and width controls.
- Undo and redo ink edits; pinch to zoom and return to fit width.
- Choose dotted, ruled, or blank paper and keep typed notes alongside each canvas.
- Save automatically, restore the last open note, and retain each note's zoom and scroll position.
- Recover the previous complete snapshot if the latest metadata or ink is unreadable. A failed save keeps the edited note open and offers Retry.

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

In Xcode, choose the **ScribbleScout** scheme and an installed iPad simulator, then Run (⌘R). There are no app accounts, API keys, environment files, or backend services to configure.

### Run on an iPad

1. Connect and unlock the iPad. Complete pairing and approve Trust if prompted.
2. Enable Developer Mode on the iPad if Xcode requests it.
3. Sign in to your Apple Account in **Xcode → Settings → Accounts**.
4. Under **ScribbleScout → Signing & Capabilities**, select your development team. The repository currently uses the BILLABYTE team; other developers should choose their own team and a bundle identifier they can sign.
5. Select the connected iPad as the run destination and Run (⌘R).

If signing fails with a rejected account login, sign in again in Xcode before retrying. Signing certificates and provisioning profiles are kept outside this repository.

## Secrets and local configuration

The notebook works without credentials. The next demo milestone uses OpenAI; no database, sync, or other provider keys are needed yet. `.env.example` lists the one credential to prepare. Model IDs will be chosen after live access is verified in [BIL-6](https://linear.app/billabyteau/issue/BIL-6/verify-live-openai-access-and-choose-supported-model-paths).

### What to prepare now

1. In the [OpenAI API platform](https://platform.openai.com/), create a separate development project for Scribble Scout, enable API billing if needed, and review its available spending controls and usage alerts. Check actual usage while testing.
2. Create a project API key with only the permissions needed for the demo. Keep the original in your password manager. Never paste it into this chat, Linear, screenshots, source code, or terminal commands/history.
3. Create a private `.env.local` from the template using the command below. Then open it in a text editor and put the key after `OPENAI_API_KEY=`. Only edit `.env.local`; leave `.env.example` empty. The command gives a new file owner-only permissions and preserves an existing file:

   ```sh
   (umask 077; cp -n .env.example .env.local)
   ```

4. `.env.local` is a plaintext local convenience for future Mac-side API checks or a backend. It is ignored by Git and is **not loaded by the current app**. Keep it outside the Xcode target and Copy Bundle Resources. Preparing the file does not enable AI yet.

### How this works in Swift

Swift/iOS does not automatically read `.env` files. Xcode scheme environment variables apply to launches from Xcode; they are not a deployment mechanism for an installed app. Copying a secret into Swift, `Info.plist`, resources, or build settings can expose it in the app or build artifacts. An ignored file protects against ordinary Git adds; it does not make a bundled value private.

The planned personal prototype ([BIL-10](https://linear.app/billabyteau/issue/BIL-10/implement-direct-openai-transport-and-user-owned-credential-controls)) will accept your own key at runtime, store it in Apple's Keychain or session memory, and offer a delete control. This credential UI is not implemented yet. Keychain is encrypted storage for a user's credentials, not a way to hide a shared developer key shipped with the app. See [Apple's Keychain guidance](https://developer.apple.com/documentation/security/using-the-keychain-to-manage-user-secrets).

For the managed TestFlight/App Store edition, the shared OpenAI key belongs in the backend's secret store. The iPad app will authenticate to that backend with a user's session. [OpenAI's authentication documentation](https://developers.openai.com/api/reference/overview#authentication) says to keep API keys out of client-side code and load them on the server. A hosted backend and authentication are later work ([BIL-25](https://linear.app/billabyteau/issue/BIL-25/build-the-minimal-authenticated-hosted-assistance-backend)). Apple signing stays managed by Xcode; don't put Apple passwords, signing private keys, or certificates in `.env` or the repo.

### Keep credentials out of commits

`.gitignore` excludes local env files, `secrets/`, `Secrets.plist`, `Secrets.xcconfig`, `*.local.xcconfig`, and signing/private-key files. Only `.env.example` is allowed, with empty values. A Python 3 pre-commit check also rejects these files even if force-added, plus likely OpenAI keys and PEM private-key headers in any staged file. It reports filenames/reasons without printing matched values.

Enable the check once per clone:

```sh
chmod +x .githooks/pre-commit
git config --local core.hooksPath .githooks
```

Before committing, verify:

```sh
git check-ignore .env.local     # should print .env.local
git ls-files '.env*'           # should list only .env.example once committed
python3 .githooks/pre-commit   # checks the staged snapshot; silent means pass
git diff --cached --stat
```

The hook checks common mistakes, not every possible secret, and can be bypassed. Review staged changes locally too. If a real key is ever committed or shared, revoke/rotate it immediately; deleting the file or adding it to `.gitignore` does not remove it from Git history. Run `python3 .githooks/test-secret-guard.py` for an isolated check of the guard.

## Using the notebook

Create a note with **New note** and edit its title at the top. Switch between **Handwriting** and **Text** to add ink or typed notes to the same record. Search matches note titles and typed text; it does not recognise handwriting yet.

In Handwriting mode, the toolbar provides the drawing tools, color, and width. **Page options** (the ellipsis button) changes paper and toggles finger drawing.

| Input mode | Write | Scroll / zoom |
| --- | --- | --- |
| Default | Apple Pencil | One finger to scroll; pinch to zoom |
| Draw with finger | Finger or Apple Pencil | Two fingers to scroll; pinch to zoom |

Keyboard shortcuts: **⌘N** creates a note, **⌘Z** undoes ink, and **⇧⌘Z** redoes ink. Ink undo history belongs to the open canvas and is not saved across app launches.

## Local storage and recovery

Notes live in the app's `Application Support/ScribbleScout` directory, with one UUID folder per note:

```text
<note-id>/
  note.json         # Current metadata, typed text, viewport, and ink filename
  previous.json     # Previous complete metadata snapshot
  <uuid>.drawing    # Original PencilKit ink, stored separately
```

Ink changes write an immutable drawing file first. The app then atomically commits metadata pointing to that file, retaining the previous complete snapshot. Obsolete ink is removed only after the commit, keeping files referenced by either snapshot. Autosave runs after a 350 ms pause; switching notes and backgrounding flush pending edits immediately.

There is no cloud sync, analytics, AI processing, or note transmission. Storage recovery protects against an interrupted save; it is not an external backup. Uninstalling the app removes its local notes. Export, deletion, and multi-page notebooks are not part of this first version.

## Tests

Unit and persistence tests use Apple's [Swift Testing](https://developer.apple.com/documentation/testing) framework, included with Xcode. Use `@Test`, `#expect`, and `#require` for new tests; use XCTest / XCUIAutomation when adding UI or performance tests. No third-party testing packages are needed.

Run **Product → Test** (⌘U) in Xcode, or use an installed simulator:

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
- Round trips for every paper style.
- Recovery from missing drawings, mismatched note IDs, and invalid drawing paths.
- Library ordering and warnings while preserving unreadable files.
- Autosave of the latest text and ink; viewport saves preserve the edit date and reuse ink.

The **Swift tests** GitHub Actions workflow runs on pushes and pull requests with Xcode 26.2 and an iPad simulator. It collects code coverage and uploads `Testing.xcresult`, which you can download and open in Xcode to inspect failures and coverage. To collect coverage locally, add `-enableCodeCoverage YES -resultBundlePath build/Testing.xcresult` to the command above; remove the previous result bundle before reusing that path. Use coverage to find missed behavior, rather than aiming for a percentage.

For a hands-on device check: create two notes, write and erase ink, undo/redo, zoom and scroll, switch notes, then background and relaunch. Confirm that the ink, typed text, and viewport survive.

## Code layout

| File | Responsibility |
| --- | --- |
| `ScribbleScout/ScribbleScoutApp.swift` | App entry point and lifecycle save |
| `ScribbleScout/Notebook.swift` | Note records, local snapshots, autosave sessions, and library state |
| `ScribbleScout/InkCanvas.swift` | PencilKit bridge, paper rendering, viewport, and ink controls |
| `ScribbleScout/NotebookView.swift` | Library, search, note editor, and drawing toolbar |
| `ScribbleScoutTests/NotebookTests.swift` | Persistence and recovery tests |

Canvas coordinates use a fixed **1,000 × 1,400 point** page, exposed by `NotebookPage.size` for future annotations. The implementation uses Apple's frameworks directly; no OwlLuna or other upstream application code was copied. Snapshot writes currently run synchronously and suit a small notebook; larger libraries may need background I/O.

## Next milestones

The roadmap is tracked in [AI Notebook: Pen to Evidence](https://linear.app/billabyteau/project/ai-notebook-pen-to-evidence-b701e6ca633c):

- [BIL-8: Local notebook foundation](https://linear.app/billabyteau/issue/BIL-8/build-the-swiftuipencilkit-workspace-with-durable-local-notes) — implemented and tested.
- [BIL-5: Device and recognition feasibility](https://linear.app/billabyteau/issue/BIL-5/verify-the-real-ipad-sdk-and-handwriting-recognition-path) — device deployment verified; recognition evaluation remains.
- [BIL-7: Shared assistance records and fixtures](https://linear.app/billabyteau/issue/BIL-7/define-shared-notebook-records-and-deterministic-provider-fixtures), followed by selected-handwriting recognition, cited research, and anchored evidence.

Audio, calendar integration, local recall, sync, and hosted services are outside this initial milestone. A project licence has not been selected yet; that decision and the full open-source release checklist remain in [BIL-24](https://linear.app/billabyteau/issue/BIL-24/prepare-a-reproducible-credential-free-open-source-release).
