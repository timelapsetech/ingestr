# Mac App Store marketing screenshots (Ingestr)

This folder contains **App Store Connect–ready** PNG screenshots generated from the same assets used on the [marketing site](../../docs/index.html) (`docs/images/`).

## Apple requirements (summary)

Per [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications) (App Store Connect Help):

- **Formats:** `.png`, `.jpg`, or `.jpeg`
- **Count:** 1–10 screenshots per listing
- **Mac size:** **16:10** screenshots. Accepted pixel sizes include 1280 × 800 through **2880 × 1800** (see [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications)).

**Requirement:** Mac screenshots are **required** for Mac apps on the App Store.

**One size is enough:** Per [Upload app previews and screenshots](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots), if the UI is the same across sizes, you can provide **only the highest-resolution** screenshots required; App Store Connect **scales them down** to other accepted sizes. This repo therefore generates **2880 × 1800** only (`marketing/app-store/screenshots/`).

Additional guidance:

- [Upload app previews and screenshots](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots) — how to add assets in App Store Connect
- [Screenshot design best practices](https://developer.apple.com/app-store/product-page/) (Product page overview; follow honest representation of the app)

Screenshots should show **real app UI** and not mislead users about functionality. The generator composites your existing UI captures into a **marketing-page-style** layout: soft gradient and accent blobs (matching the site palette), **feature cards** with copy aligned to `docs/index.html`, and a **large rounded window** with drop shadow on the right. Regenerate after updating `docs/images/` sources or editing `scripts/generate_app_store_mac_screenshots.py`.

## What’s included

| File | Description |
|------|----------------|
| `screenshots/01-main-window.png` | Main window: source/output, options, Start Ingesting |
| `screenshots/02-progress-and-status.png` | Second marketing angle: large jobs / progress / verification copy + same main window |

Both are **2880 × 1800**. Upload these to App Store Connect; smaller display sizes are derived automatically when applicable.

## Regenerate

From the repository root:

```bash
python3 scripts/generate_app_store_mac_screenshots.py
```

Requires [Pillow](https://python-pillow.org/) (`pip install pillow` if needed).

## Privacy policy URL

App Store Connect asks for a **Privacy Policy URL**. Use the deployed page:

`https://<your-github-pages-host>/ingestr/privacy.html`

(or your custom domain path to `privacy.html`).

Contact for privacy questions: **privacy@timelapsetech.com** (also listed in the policy).

## Optional next steps

- Capture additional **native** window shots (e.g. completion alert, Finder reveal) in Xcode and add slides by extending `scripts/generate_app_store_mac_screenshots.py`.
- Provide **localized** screenshots per language if you localize the App Store listing.
