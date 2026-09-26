# TalkStrangers Mobile (Flutter) — Feature-Parity Build v3

This Flutter client was reconstructed from the uploaded **talkstrangersfrontend** React/Vite application and the **talkstrangersbackend** Spring Boot API. It contains the **caller/user and listener experience only**. Admin dashboards and admin-only operations are intentionally excluded.

## Install at the requested Windows location

Extract the archive so this folder exists:

`C:\Users\PandeyAman\Documents\talkstrangers\talkstrangersmobile`

Then open PowerShell in that directory and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\bootstrap_windows.ps1
```

The bootstrap script uses the Flutter SDK installed on your PC to create the Android/iOS platform folders, restores the migrated Dart source, configures camera/microphone/network permissions, installs the Android privacy/voice-effects bridge, and runs `flutter pub get`.

Run the Spring Boot backend on port 8080, then use one of these commands.

Android emulator:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/api/v1
```

Physical Android phone on the same Wi-Fi:

```powershell
flutter run --dart-define=API_BASE_URL=http://YOUR_PC_LAN_IP:8080/api/v1
```

For Google Sign-In also provide the Web OAuth server client ID:

```powershell
flutter run --dart-define=API_BASE_URL=http://YOUR_PC_LAN_IP:8080/api/v1 --dart-define=GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID
```

Use HTTPS in production and disable development clear-text HTTP before Play Store release.

## Caller/user parity implemented

- Anonymous mobile OTP authentication and Google authentication, controlled by backend auth-governance settings.
- Anonymous nickname, avatar and bio profile; nickname regeneration and avatar upload.
- Listener discovery, search, category filtering, availability/presence state, profile details and reviews.
- Follow/unfollow/favourites, followed-listener screen, offline nudge and persisted nudge status.
- Instant chat, voice and video session requests, ringing countdown/status polling, cancellation and reconnect handling.
- REST WebRTC signaling through the existing backend, ICE configuration, camera/microphone/speaker controls and connection recovery.
- Persistent in-session chat, virtual gifts, wallet-aware gifting, icebreakers, synchronized Tic-Tac-Toe, Would You Rather and 20 Questions.
- Voice privacy-effect selector and synchronized peer state. Normal WebRTC audio remains interoperable with web/iOS; Android native PCM effects activate only when both mobile peers advertise support.
- Video privacy filters/masks and synchronized peer filter state.
- Wallet balance, Razorpay recharge flow and searchable/filterable transaction ledger.
- Detailed caller session history with search/filter/sort, receipts, transcripts, gift history, review submission, reconnect/contact-again and support/report/block actions.
- Legacy scheduled consultation flow from the source application: slots, agenda, booking creation, booking receipt, cancellation, dispute flow and scheduled-call screen.
- Callback invitation handling when a listener calls a caller back.
- Notifications with unread badge, mark read/all read and clear-all operations.
- Safety/support center with block list, unblock, block history, inquiries, inquiry status and admin replies.
- How It Works caller/listener guide and FAQs.
- 10-minute inactivity logout outside a live session, matching the web behavior.
- Five-second authenticated-account watcher so suspension/token/account changes are reflected without restarting the app.

## Listener parity implemented

- Listener email/password login, forgot/reset password and listener registration.
- Registration rate-limit awareness, taxonomy fields and media upload used by listener onboarding.
- Listener profile editor with identity/contact/profile fields, rates, categories, languages, availability-related settings, profile photo upload and verification submission.
- Online/offline presence, presence heartbeat and forced offline behavior on logout.
- Listener dashboard with wallet/session/rating metrics, live daily online-time counter, three-hour daily target, attendance/missed-day status and policy messaging.
- Incoming instant-session polling and accept/reject handling.
- Nudge notification polling and quick Go Online action.
- Chat, voice and video participation through the same shared session/WebRTC implementation.
- Session heartbeat, reconnect behavior and clean session termination.
- Listener session history with search/filter/sort, receipt, transcript, gifts and callback flow.
- Missed-session callback invitation with polling until caller accepts or the request expires.
- Earnings/wallet transaction filtering, session/gift earnings summaries, payout history and UPI payout request validation.
- Listener reviews, date filtering and public listener responses.
- Weekly availability rules plus blackout/special-time availability exceptions.
- Notifications, safety/block management and support inquiries.

## Privacy and media equivalence

The web application and a Flutter mobile application cannot use identical browser APIs, so browser-only mechanics are implemented with mobile equivalents:

- The React app uses browser shortcut/getDisplayMedia interception. Android uses backend-controlled `FLAG_SECURE` to prevent screenshots/screen recording. Android does not expose a reliable callback for every blocked screenshot attempt, so the browser keyboard-shortcut audit event itself has no exact Android equivalent.
- The React app uses Web Audio/Canvas APIs for media effects. Flutter uses WebRTC rendering plus the Android native voice-effects bridge included in `bootstrap_windows.ps1`. To avoid breaking Android ↔ web/iOS calls, natural audio always uses standard WebRTC; a non-natural Android voice effect is enabled only when the other participant is also a compatible TalkStrangers Android client.
- The web call page's recording helper currently exits without recording user/listener sessions. This mobile build likewise does **not** secretly record calls.

See `PARITY_AUDIT.md` for the detailed source-to-mobile feature audit and `MIGRATION_MAP.md` for file mapping.

## Validation status

The migration was statically checked for missing local Dart imports, delimiter balance and calls to undefined `ApiService` methods. Those checks pass.

A Flutter SDK/Android toolchain is not available in the generation environment, so a real `flutter analyze`, Gradle build, emulator run and two-device WebRTC test must be performed on your Windows machine before release.

After bootstrapping, run:

```powershell
flutter analyze
flutter build apk --debug
```

Then test caller ↔ listener chat, audio, video, Razorpay, Google Sign-In, callbacks, gifts, games, filters, payouts and privacy behavior on real Android devices.

## Release checklist

- Use your production HTTPS backend URL.
- Configure the final Android application ID and Google OAuth SHA-1/SHA-256 fingerprints.
- Test Razorpay with the intended account/mode.
- Verify Play Console camera/microphone declarations and privacy policy.
- Test WebRTC across different networks. Add/configure TURN infrastructure if your production network environment needs relay connectivity.
- Rotate the credentials listed in `SECURITY_ACTION_REQUIRED.md` before production.
