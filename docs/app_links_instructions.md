Android Digital Asset Links (assetlinks.json)

- File URL: https://smartdisplay.mareo.ai/.well-known/assetlinks.json
- Example content (replace placeholders):

[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "REPLACE_WITH_ANDROID_PACKAGE",
      "sha256_cert_fingerprints": [
        "REPLACE_WITH_RELEASE_KEY_SHA256"
      ]
    }
  }
]

- Get SHA256 fingerprint:
  - If using keystore: `keytool -list -v -keystore your_keystore.jks -alias your_alias -storepass ***** -keypass ***** | grep SHA256` 

iOS Apple App Site Association (AASA)

- File URL: https://smartdisplay.mareo.ai/apple-app-site-association
- Content-Type: application/json (no .json extension)
- Example content (replace placeholders):

{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "TEAMID.BUNDLE_ID",
        "paths": [
          "/ios-launch",
          "/android-launch",
          "*"
        ]
      }
    ]
  }
}

- Get TEAMID: from Apple Developer account; BUNDLE_ID from Xcode `PRODUCT_BUNDLE_IDENTIFIER`.

Notes

- The actual link the user taps must match the host/path above to trigger app opening.
- After deploying files, reinstall the app to refresh associations.

