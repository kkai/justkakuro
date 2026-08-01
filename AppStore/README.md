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

## Build upload

`~/.appstoreconnect/private_keys/AuthKey_49X742Y226.p8` is where `altool` looks
for the API key. With it in place the whole path is non-interactive:

    xcodebuild archive -project Kakuro.xcodeproj -scheme Kakuro \
      -configuration Release -destination 'generic/platform=iOS' \
      -archivePath build/JustKakuro.xcarchive -allowProvisioningUpdates \
      -authenticationKeyPath <p8> -authenticationKeyID 49X742Y226 \
      -authenticationKeyIssuerID <issuer>

    xcodebuild -exportArchive -archivePath ... -exportOptionsPlist ExportOptions.plist \
      -allowProvisioningUpdates -authenticationKey...

    xcrun altool --validate-app -f Kakuro.ipa -t ios --apiKey ... --apiIssuer ...
    xcrun altool --upload-app   -f Kakuro.ipa -t ios --apiKey ... --apiIssuer ...

Note the archive step signs with the *development* identity; distribution
signing is applied at export. Passing the authentication key to both steps lets
Xcode create the App Store provisioning profile and use a Cloud Managed
distribution certificate without a human, which matters because no distribution
certificate is present in this machine's keychain.

Always run `--validate-app` first. It catches icon, version and entitlement
problems without consuming an upload.

## In-app purchase image

`iap/generate.py` draws `iap/just-kakuro-full.png` (1024x1024, RGB, no alpha):
lesson two's board, solved. Upload it against the IAP's `images` relationship:

    POST /v1/inAppPurchaseImages

The relationship is named `inAppPurchase`, not `inAppPurchaseV2`, even though
the IAP itself is read from the `/v2/` endpoints. Its readiness shows up as
`state`, not `assetDeliveryState`; `PREPARE_FOR_SUBMISSION` is the healthy value.
