# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4] - 2026-05-04
### Added
- **Ingest mode** on the main window: choose **Sequence mode** (existing behavior—detect sequences, Extras, auto rename, add to existing) or **Photo mode** (no sequence grouping). Photo mode places each file under `Output/Year/Month/Day/` and renames it to a capture-time stamp `yyyy-MM-dd-HHmmss-SSS` (with collision suffixes if needed). Tooltips on each mode summarize an example path.
- **Window size** default increased so the main window fits the new controls on first launch.

### Changed
- **Copy verification** default is now **Full** (byte-for-byte check after copy) for new installs and when no preference is saved. **None** remains available for maximum speed; a previously saved mode in settings is still respected.

### Fixed
- **Auto Split**: Crash (“index out of range”) when every gap between shots was filtered out as unusable cadence—for example identical capture timestamps or only extreme gaps. Ingest now falls back safely (no median interval) instead of trapping.
- **Open Folder** (completion alert): Could fail under App Sandbox after ingest because security-scoped access to the destination had been released. The app temporarily restores scoped access before asking Finder to reveal the folder.

### Improved
- **Copy phase**: Status shows **which file is copying** before each file starts (important when **Full** verification spends a long time on large originals). Streaming SHA-256 copy **yields periodically** so the UI stays responsive during heavy files.

## [1.3] - 2026-04-19
### Added
- **Copy verification** (Rename Options): choose **None** (default, same behavior as before), **Full** (streaming SHA-256 copy plus destination hash check), or **Size only** (compare file sizes after copy). The choice is saved between launches.

## [1.2] - 2026-04-17
### Added
- Click the source or output drop zone to open a folder picker (in addition to drag-and-drop).
- Per-step progress detail during ingest (e.g. current file while reading metadata and while copying).

### Improved
- Ingest work runs off the main thread so the window stays responsive; progress updates during metadata reads and copies (including small sequences moved to Extras).
- Weighted progress: metadata pass and copy phase each contribute to the bar proportionally.
- Start Ingesting is disabled while a run is in progress.
- Clearer message when no files match the current settings (extension filter, folder access, etc.).

### Changed
- Release build entitlements no longer include debug-oriented hardened-runtime exceptions (JIT, unsigned executable memory, etc.); distribution should rely on normal signing and notarization.

## [1.1] - 2025-05-18
### Added
- "Add to Existing" option: Continue numbering in an existing image sequence, matching zero-padding and appending new images without overwriting.
- Automated unit tests for sequence detection, filename generation, and add-to-existing logic.

### Improved
- Output file naming is now more robust, always matching the underscore and padding style of existing sequences.
- The "Open Folder" button now opens the actual sequence folder after ingest completes.

### Fixed
- Various edge cases in sequence detection and file naming.

## [1.0] - 2025-05-17
- Initial release.

### Added
- Initial release
- Smart sequence detection
- Auto rename functionality
- Auto split sequences
- Extras handling
- File extension filtering
- Progress tracking
- Dark/Light mode support
- Modern drag-and-drop interface

### Known Issues
- None at this time 