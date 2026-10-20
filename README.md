# Scribble Scout

An iPad notebook built with SwiftUI and PencilKit, with handwriting, typed notes, and local storage.

## Features

- Apple Pencil and optional finger drawing, with pen, highlighter, eraser, and lasso tools.
- Typed notes, title and text search, and dotted, ruled, or blank paper.
- Undo and redo for ink, page zoom, and a saved viewport for each note.
- Automatic local saving with a previous snapshot for recovery.

## Running the app

Open `ScribbleScout.xcodeproj` in Xcode, select the `ScribbleScout` scheme, and run on an iPad simulator or device with iOS 18 or later. For a physical device, select your development team in Signing & Capabilities.

The `ScribbleScoutTests` target covers local note persistence and recovery. Run it with Product > Test in Xcode.

AI features are not yet implemented.
