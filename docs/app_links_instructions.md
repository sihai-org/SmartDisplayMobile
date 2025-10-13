Android Digital Asset Links (assetlinks.json)

- File URL: https://m.smartdisplay.mareo.ai/.well-known/assetlinks.json
- Example content (replace placeholders):

[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.datou.smart_display_mobile",
      "sha256_cert_fingerprints": [
        "REPLACE_WITH_RELEASE_KEY_SHA256"
      ]
    }
  }
]

- Get SHA256 fingerprint:
  - If using keystore: `keytool -list -v -keystore your_keystore.jks -alias your_alias -storepass ***** -keypass ***** | grep SHA256` 

iOS Apple App Site Association (AASA)

- File URL: https://m.smartdisplay.mareo.ai/apple-app-site-association
- Content-Type: application/json (no .json extension)
- Example content (replace placeholders):

{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "TEAMID.BUNDLE_ID",
        "paths": [
          "/connect",
          "/launch.html"
        ]
      }
    ]
  }
}

- Get TEAMID: from Apple Developer account; BUNDLE_ID from Xcode `PRODUCT_BUNDLE_IDENTIFIER`.

Notes

- Unified custom scheme: `smartdisplay`.
  - iOS/Android both handle: `smartdisplay://connect?...`
- Universal/App Links host: `m.smartdisplay.mareo.ai` (ensure DNS/HTTPS ready).
- Android Intent example (from web):
  - `intent://connect?{QUERY}#Intent;scheme=smartdisplay;package=com.datou.smart_display_mobile;end`
- The actual link must match the host/path above to trigger opening.
- After deploying AASA/assetlinks, reinstall the app to refresh associations.
