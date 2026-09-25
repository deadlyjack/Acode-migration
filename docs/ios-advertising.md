# iOS advertising

iOS has one free app, built with the `runner` target and scheme using the bundle
ID from `package.json.appleAppId`. It links Google Mobile Ads 13.10.0 and User
Messaging Platform 3.1.0 through Swift Package Manager. The iOS native and web
builds always include the free implementation, regardless of the Android edition
in `package.json.androidPackageId`.

`platforms/ios/ads` adapts the original AdMob Plus iOS format implementations and
native-ad XIB from [admob-plus](https://github.com/admob-plus/admob-plus) at commit
`16e5768bda7244e8d35334a62caa5dbcadd70c9a` (the `cordova` and `cordova-native`
packages). Its MIT notice is retained in `AdMobPlus-LICENSE.txt`. The WebView ad
registration follows the upstream `cordova-webview-ad` implementation; its bridge
methods retain Acode's Android adapter contract. Native classes are regular Xcode
sources; there is no plugin installation, native code generation or copying hook.

The port replaces the command/callback transport and global plugin registry with
the existing iOS bridge. It retains banner, interstitial, rewarded, rewarded
interstitial, app-open and native formats, server-side reward options, request
configuration, event names and IDs. Paid impression events use the same payload
as Android. Banner layout reserves space in the editor's existing wrapper and
accounts for safe areas and the keyboard without reparenting the WebView.
The shared request builder supplies the presenting window's `UIWindowScene`, as
recommended by Google's [iPad window guide](https://developers.google.com/admob/ios/multiscene),
so the SDK receives the app window's sizing context for every ad format.

Pending loads are invalidated on replacement, destroy and WebView reload. Native
views, delegates and paid-event handlers are released. Fullscreen presentation is
limited to one ad in a foreground app; reward values are captured before
presentation so dismissal cannot lose the reward callback. The SDK integration
page opens in a separate sheet with no app native bridge.

The existing JavaScript consent coordinator uses UMP's current-session state.
Native initialization, loads and presentation require `canRequestAds`; no stored
boolean substitutes for UMP. Consent forms are loaded separately from presentation
so a form loaded for an old WebView cannot appear after reload. Privacy options
remain accessible through the shared settings entry. Consent reset and geography
overrides are limited to debug builds. ATT is requested only by an explicit API
call or an IDFA message configured in UMP.

Reward passes retain Android's rules: Quick grants one hour; Focus grants four,
five or six hours, with three redemptions per local calendar day and at most ten
hours remaining. Native state lives in the existing `ads` Keychain namespace.
Tests cover midnight resets, stacking and clipping, expiry notification delivery,
persisted state and malformed-state recovery. The shared rewarded-ad gate accepts
iOS; it still enforces the existing Android SDK minimum on Android.

## Configuration

Debug builds use Google's published [iOS test ad units](https://developers.google.com/admob/ios/test-ads)
and sample app ID. Set `ACODE_IOS_ADMOB_APP_ID` to a configured iOS app ID to test
that app's consent messages; debug ad units remain Google's test units.

Release builds require all four environment variables:

- `ACODE_IOS_ADMOB_APP_ID`
- `ACODE_IOS_ADMOB_BANNER_ID`
- `ACODE_IOS_ADMOB_INTERSTITIAL_ID`
- `ACODE_IOS_ADMOB_REWARDED_ID`

The release script rejects missing, malformed and Google demo IDs. Use iOS IDs;
Android ad-unit IDs are not a substitute. No production IDs are committed.
`dev/scripts/iosAds.js` creates `.ios-build/App-Info.plist` from the shared app
metadata and adds the SDK keys. `dev/ios/skadnetwork.json` is the
50-entry list from Google's [setup guide](https://developers.google.com/admob/ios/quick-start),
retrieved on 2026-09-23. Refresh it when updating the SDK. Run the normal build
script before building `runner` directly in Xcode so its metadata and web
bundle match the build mode.

The deprecated anchored banner size helpers and legacy child-directed/under-age
request fields are retained to preserve the existing public API's dimensions and
separate option semantics. Switching to the newer large banners or combined age
policy would be a behavior change.

## Validation boundaries

Automated simulator checks use actual SDK classes with network loads replaced only in the
banner layout fixture. They cover advertising inclusion, the app identity, API dispatch, consent gating,
load invalidation, callback isolation, paid-impression format/currency payloads,
stacking/hiding/destroying banners, native
XIB loading and fullscreen ownership. Shared tests cover iOS ID selection,
unchanged Android behavior, initialization retries and release configuration.
A scene regression failed for all six native formats before the shared request
builder supplied the presenting scene; all six AdMob bridge tests pass with it.

A sample UMP form was observed in the simulator. The regression test bootstrap
suppresses automatic consent gathering so unrelated tests do not depend on network
dialogs; direct bridge calls still test the native consent gate. This fixture is
only in the test bundle and does not modify normal app launches or stored Pro status.
A normal free-edition launch on iOS 18.6 also displayed the system ATT prompt.
Choosing Ask App Not to Track left an incoming Files document editable and savable.

A normal free-app launch on the iPad iOS 18.6 simulator also loaded Google's
adaptive banner and rewarded test creatives, visibly labelled Test mode. The
Settings banner stayed inside Acode's Split View area, hid when the software
keyboard opened, returned after dismissal and adapted to portrait rotation.
The Quick pass flow showed Reward granted in the SDK creative; dismissing it
changed the app from no active pass and 0/3 redemptions to one hour remaining and
1/3 redemptions. Returning to Settings suppressed its previously visible banner.
This used the normal app UI and published Google test units, without consent or
ad-load mocks. Further banner checks must account for any active rewarded pass.

A temporary manual bridge harness also loaded Google's interstitial test unit on
iOS 18.6. On the iPad in Split View, closing the SDK's Test mode screen delivered
`load`, `show`, `impression` and `dismiss` in order. The active editor document,
unsaved state, WebView frame and stored reward pass were unchanged; the native
fullscreen owner and loaded ad were released. Native consent gathering and ad
loading were real. The harness called the public ad API directly, so this does
not establish normal app interstitial eligibility during an ad-free pass.

The iPad's landscape Split View creative area was intermittently black, both
before and after the scene correction. Subsequent portrait and landscape runs
rendered the full test image and passed manual dismissal with editor content,
layout and reward state preserved. In the final landscape run, the SDK's
`canPresent` preflight accepted the window and its ad WebView matched the app's
991-by-1032-point window. This does not establish the cause of the intermittent
black creative. Google's window guide still documents portrait-only support for
Split View ads; physical-device validation remains necessary.

The same test unit rendered the full Google test image on the iPhone simulator.
Its manual dismissal check timed out because the desktop UI tool could not
reliably target the close control; it is not a passing iPhone dismissal test.
The temporary presentation and rendering harnesses were removed from the suite.

These checks do not prove production ad delivery or revenue, account-configured
consent forms, mediation adapters or physical-device presentation. Production
AdMob configuration, broader consent/ATT variants and physical-device ad layout
during keyboard changes, rotation and fullscreen remain unverified.
