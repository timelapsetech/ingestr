# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1] - 2024-06-XX
### Added
- "Add to Existing" option: Continue numbering in an existing image sequence, matching zero-padding and appending new images without overwriting.
- Automated unit tests for sequence detection, filename generation, and add-to-existing logic.

### Improved
- Output file naming is now more robust, always matching the underscore and padding style of existing sequences.
- The "Open Folder" button now opens the actual sequence folder after ingest completes.

### Fixed
- Various edge cases in sequence detection and file naming.

## [1.0] - 2024-XX-XX
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