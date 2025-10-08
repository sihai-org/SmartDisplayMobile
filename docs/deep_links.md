Deep Links Setup (Android App Links & iOS Universal Links)

Overview
- Use HTTPS links: https://datou.com/...
- Android: App Links with assetlinks.json on your domain.
- iOS: Universal Links with Associated Domains and apple-app-site-association on your domain.

Android
1) AndroidManifest
   - MainActivity has an intent-filter with android:autoVerify="true" for https + datou.com.
   - Path prefix is "/" to allow all pages, refine if needed.

2) Digital asset links (on your HTTPS domain)
   - Host this JSON at: https://datou.com/.well-known/assetlinks.json

   Example (replace package name and SHA256):
   [
     {
       "relation": ["delegate_permission/common.handle_all_urls"],
       "target": {
         "namespace": "android_app",
         "package_name": "YOUR_ANDROID_PACKAGE",
         "sha256_cert_fingerprints": [
           "AA:BB:CC:...:ZZ"
         ]
       }
     }
   ]

   - Get SHA-256 signing cert fingerprint:
     - Debug: `keytool -list -v -alias androiddebugkey -keystore ~/.android/debug.keystore -storepass android -keypass android`
     - Release: from your release keystore or Play Console.

3) Verification
   - Install the app, then `adb shell pm get-app-links YOUR_ANDROID_PACKAGE` to see verification state.
   - Tapping https://datou.com/home should open the app once verified.

iOS
1) Associated Domains capability
   - Enable in Xcode (Runner target > Signing & Capabilities): add Associated Domains with: `applinks:datou.com`.
   - This creates/updates `ios/Runner/Runner.entitlements`.

2) apple-app-site-association (AASA)
   - Host at: https://datou.com/apple-app-site-association (no extension, JSON, served as application/json)

   Example:
   {
     "applinks": {
       "details": [
         {
           "appID": "TEAMID.BUNDLE_ID",
           "paths": [ "/", "*" ]
         }
       ]
     }
   }

   - TEAMID: your Apple Developer Team ID
   - BUNDLE_ID: iOS bundle identifier (e.g., com.datou.app)

3) Test
   - Install app on device, then open Notes/Safari with a link like https://datou.com/home and tap it.

Flutter code
- We normalize incoming URIs to canonical paths in `lib/presentation/pages/splash_page.dart`.
- App Links (https) will yield `uri.path` like `/home`, which routes to the correct page.

Operational notes
- Propagation/verification can take time; ensure HTTPS with valid cert.
- Keep the old custom scheme only if you need legacy QR codes; prefer HTTPS in new materials.
