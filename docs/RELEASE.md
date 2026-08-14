# Releasing Ingestr

Use this checklist when cutting a new **macOS** release (GitHub download or App Store).

## 1. Version numbers

Update these together for every release:

| Location | Keys |
|----------|------|
| `Ingestr.xcodeproj` → Ingestr target | `MARKETING_VERSION` (user-facing, e.g. `1.6.1`), `CURRENT_PROJECT_VERSION` (build number, e.g. `9`) |
| `Ingestr/Info.plist` | Uses `$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)` — no manual edit needed |
| `CHANGELOG.md` | Move `[Unreleased]` into a dated section |
| `README.md` | **Current release** line |
| `docs/index.html` | Hero “Current release” line |

IngestrTests `MARKETING_VERSION` should match the app for consistency.

## 2. Pre-flight

```bash
# From repository root
xcodebuild -scheme Ingestr -destination 'platform=macOS' test
xcodebuild -scheme Ingestr -configuration Release -destination 'platform=macOS' build
```

Or in Xcode: **Product → Test** (⌘U), then **Product → Build** (⌘B) with the **Release** configuration.

## 3. Archive and export

1. Open `Ingestr.xcodeproj` in Xcode.
2. Select scheme **Ingestr** and destination **My Mac**.
3. **Product → Archive**.
4. In the Organizer: **Distribute App** → **Developer ID** (direct download) or **App Store Connect** (Mac App Store).
5. Enable **notarization** for Developer ID builds (required for Gatekeeper on other Macs).

Release configuration uses `Ingestr/IngestrRelease.entitlements` (App Sandbox, user-selected read-write, pictures).

## 4. GitHub release asset

After export, zip the app for direct download:

```bash
cd /path/to/exported
ditto -c -k --sequesterRsrc --keepParent Ingestr.app Ingestr.zip
```

Upload `Ingestr.zip` to a [GitHub Release](https://github.com/timelapsetech/ingestr/releases) tagged `v1.6.1` (match `MARKETING_VERSION`). The site and README link to:

`https://github.com/timelapsetech/ingestr/releases/latest/download/Ingestr.zip`

Optional: copy the zip to `Release/Ingestr.zip` in the repo only if you intentionally commit release binaries (usually prefer GitHub Release assets only).

## 5. Git tag

```bash
git tag -a v1.6.1 -m "Ingestr 1.6.1"
git push origin v1.6.1
```

## 6. After release

- Confirm **Open Folder**, **Auto Rename + Auto Split** (including **Variation %**), and output-folder permissions on a real card dump.
- Update App Store Connect version/build if you ship the Mac App Store listing.
- Deploy docs if you host `docs/` on GitHub Pages (`docs/index.html`, `docs/guide.html`).
