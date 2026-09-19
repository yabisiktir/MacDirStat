# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
swift build                # Debug build
swift build -c release     # Release build
swift run MacDirStat       # Run the app
open Package.swift         # Open in Xcode
```

No external dependencies. Unit tests live in `Tests/MacDirStatTests` (`swift test`), covering the FileNode aggregation, categorization, byte formatting, and the treemap layout engine. No linter configured; Swift 6 strict concurrency mode is enforced via `swiftLanguageMode(.v6)` in Package.swift.

CI runs build + tests on every push/PR (`.github/workflows/ci.yml`); tagging `v*` builds and attaches a packaged `.app` zip to a GitHub release (`.github/workflows/release.yml`).

## Architecture

MacDirStat is a native macOS (15.0+) SwiftUI disk space analyzer that visualizes directory usage as interactive treemaps. Swift 6, SPM-only, zero external dependencies.

### State & Data Flow

**AppState** (`@Observable`) is the single source of truth. It holds the scanned file tree (`rootNode: FileNode`), the current treemap view root (`treemapRoot`), selected node, and breadcrumb navigation stack. All views react to AppState changes.

Scan flow: User picks folder → **ScanCoordinator** launches **FileScanner** → FileScanner walks the tree with BSD `opendir`/`readdir` + `fstatat` (not FileManager, for performance), scanning sibling subdirectories concurrently via structured `TaskGroup`s → yields `ScanEvent`s via `AsyncStream` → ScanCoordinator throttles updates (50ms) and receives the finished **FileNode** tree → treemap renders.

### Module Layout (Sources/MacDirStat/)

- **App/** — Entry point (`MacDirStatApp`) and `AppState` central state management
- **Scanning/** — `FileScanner` (concurrent `opendir`/`readdir`/`fstatat` traversal with inode dedup, cross-device skipping, allocated size via blocks×512), `ScanCoordinator` (async orchestration, throttling, cancellation), `FileNode` (tree model with weak parent refs to avoid retain cycles, recursive aggregate computation)
- **Categorization/** — `FileCategory` (10 categories with colors/SF Symbols) and `FileExtensionMap` (200+ extension→category mappings)
- **Treemap/** — `TreemapLayoutEngine` (Squarify algorithm, max 12 depth levels), `TreemapRenderer` (Canvas-based with depth-darkened category colors), `TreemapView` (click/double-click/hover/context menu interactions, layout computed off the main actor), `ZoomPanOverlay` (`NSViewRepresentable` capturing scroll/magnify/middle-drag for zoom & pan)
- **Views/** — `ContentView` (NavigationSplitView: sidebar tree + center treemap + inspector), `WelcomeView` (volume list with usage bars, NSOpenPanel), `ScanProgressView`, `DirectoryTreeView` (OutlineGroup), `DetailPanelView` (metadata + category breakdown)
- **Utilities/** — `ByteFormatter` (human-readable sizes)

### Key Patterns

- All data types crossing async boundaries are `Sendable`
- FileNode uses weak parent references to break retain cycles
- FileScanner deduplicates hard links by tracking seen inodes
- TreemapView uses Canvas for rendering (not individual SwiftUI views) for performance
- macOS APIs used: `NSWorkspace` (Reveal in Finder), `NSPasteboard` (clipboard), `NSOpenPanel` (folder picker)
