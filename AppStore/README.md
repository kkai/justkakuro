# App Store assets for Just Kakuro

## Pages to host

Upload both files to `https://kaikunze.de/justkakuro/`:

- `index.html` -> https://kaikunze.de/justkakuro/
- `justkakuro-privacy.html` -> https://kaikunze.de/justkakuro/justkakuro-privacy.html

Both URLs are already set in App Store Connect and both currently return 404.
App Review resolves them, so they must be live before submitting.

## Metadata

`metadata/` holds exactly what was uploaded to App Store Connect (en-US, v1.0).
Re-upload with:

    appship metadata --bundle-id de.kaikunze.kakuro \
      --description-file metadata/description.txt \
      --keywords-file metadata/keywords.txt \
      --promo-file metadata/promo.txt

Note: `whatsNew` cannot be set on a first release; App Store Connect rejects it.

## Screenshots

Captured by driving the simulator, from real gameplay. iPhone 16 Pro Max
(1320x2868, display type APP_IPHONE_67) and iPad Pro 13-inch (2064x2752,
APP_IPAD_PRO_3GEN_129), flattened to RGB.

AppShip uploads iPhone screenshots as APP_IPHONE_65, which rejects 1320x2868
with IMAGE_INCORRECT_DIMENSIONS while still reporting success. The iPhone set
was uploaded directly against the API instead. Check
`appScreenshots.assetDeliveryState` after any upload rather than trusting the
tool's output.

Screenshots of the paid tier need the unlock, which a simulator cannot buy. The
app accepts `-KakuroScreenshotUnlock` for that, wrapped in `#if DEBUG` so it
cannot exist in a shipped build (`ReleaseBuildTests`, plus a `strings` check on
a Release binary).
