# TalkStrangers web → Flutter parity audit (v3)

Scope: all caller/user and listener functionality found in the uploaded React source, plus the existing Spring Boot endpoints those flows use. Admin-only functionality is intentionally excluded.

Status terminology:

- **Implemented** — represented in Flutter and wired to the existing backend API.
- **Mobile equivalent** — same user-facing purpose, implemented differently because the web version depends on browser-only APIs.
- **Legacy/source flow included** — source code exists even though current React routing redirects or de-emphasizes the flow; it is still included in Flutter for completeness.
- **Device validation required** — implementation is present but cannot be runtime-tested in the generation environment.

## Authentication and account lifecycle

| Capability | Status | Flutter area |
|---|---|---|
| Caller OTP sign-in | Implemented | `auth/login_screen.dart` |
| Caller Google sign-in | Implemented; device OAuth config required | `auth/login_screen.dart`, `core/app_controller.dart` |
| Backend auth-governance switches | Implemented | `core/app_controller.dart` |
| Listener email/password sign-in | Implemented | `auth/login_screen.dart` |
| Listener forgot/reset password | Implemented | `auth/login_screen.dart` |
| Listener registration | Implemented | `auth/listener_register_screen.dart` |
| Five-second account/session validity watcher | Implemented | `core/app_controller.dart` |
| Ten-minute inactivity logout, skipped during live session | Implemented | `core/inactivity_guard.dart` |
| Listener set offline during logout | Implemented | `core/app_controller.dart` |

## Caller identity and listener discovery

| Capability | Status | Flutter area |
|---|---|---|
| Anonymous profile | Implemented | `caller/anonymous_profile_screen.dart` |
| Nickname regeneration | Implemented | same |
| Avatar upload | Implemented | same |
| Browse/search listeners | Implemented | `caller/caller_home_screen.dart` |
| Categories/filtering | Implemented | same |
| Online/offline/busy presence | Implemented | home/detail screens |
| Listener detail/rates/profile/reviews | Implemented | `caller/listener_detail_screen.dart` |
| Follow/unfollow | Implemented | home/detail screens |
| Followed-listener list | Implemented | `caller/followed_listeners_screen.dart` |
| Offline nudge | Implemented | listener detail/home |
| Persisted nudge status | Implemented | listener detail/home |
| Blocked users hidden from discovery | Implemented | `services/api_service.dart` |
| "blocked by listener" visibility check | Implemented | `services/api_service.dart` |

## Instant sessions and live communication

| Capability | Status | Flutter area |
|---|---|---|
| Chat request/ringing/status | Implemented | detail/home + `session_screen.dart` |
| Audio request/ringing/status | Implemented | same |
| Video request/ringing/status | Implemented | same |
| Caller cancel | Implemented | session flow |
| Listener accept/reject | Implemented | `listener/listener_shell.dart` |
| Session start/heartbeat/end | Implemented | `session/session_screen.dart` |
| ICE/server signaling bridge | Implemented | `session_screen.dart`, `api_service.dart` |
| Camera/microphone controls | Implemented | `session_screen.dart` |
| WebRTC ICE restart/reconnect window | Implemented | `session_screen.dart` |
| Session chat history | Implemented | live screen + history screens |
| Persistent in-call chat | Implemented | `session_screen.dart` |
| Virtual gifts | Implemented | `session_screen.dart` |
| Gift history | Implemented | caller/listener history |
| Icebreaker topic | Implemented | `session_screen.dart` |
| Tic-Tac-Toe | Implemented, synchronized signaling | `widgets/in_call_mini_games.dart` |
| Would You Rather | Implemented, synchronized signaling | same |
| 20 Questions | Implemented, synchronized signaling | same |
| Video privacy effects | Implemented | `widgets/video_privacy_filter.dart` |
| Voice privacy effects | Android mobile-to-mobile native bridge implemented; natural audio remains standard WebRTC for web/iOS interoperability; device validation required | `services/android_voice_fx.dart`, bootstrap native code |
| Peer filter synchronization | Implemented | `session_screen.dart` |
| Report/block during/after session | Implemented | session/history/safety screens |
| Review/rating after session | Implemented | caller history / end flow |
| Callback from listener to caller | Implemented | listener history/dashboard + `caller_shell.dart` |

## Wallet, billing, earnings and payouts

| Capability | Status | Flutter area |
|---|---|---|
| Wallet balance | Implemented | `caller/wallet_screen.dart`, shells |
| Razorpay create-order/verify | Implemented; device validation required | wallet screen |
| Wallet transaction ledger | Implemented | wallet screen |
| Transaction search/type/date filters | Implemented | wallet screen |
| Gift debit/credit display | Implemented | wallet/earnings screens |
| Listener earning summaries | Implemented | `listener/listener_earnings_screen.dart` |
| Payout history | Implemented | same |
| UPI payout request | Implemented | same |

## Histories, receipts, support and safety

| Capability | Status | Flutter area |
|---|---|---|
| Caller session history | Implemented | `caller/caller_history_screen.dart` |
| Search/filter/date/sort | Implemented | same |
| Session receipt/details | Implemented | same |
| Transcript | Implemented | same |
| Gift details | Implemented | same |
| Connect again | Implemented | same |
| Support inquiry | Implemented | history + `common/safety_support_screen.dart` |
| Inquiry status/admin reply | Implemented | safety/support screen |
| Block list | Implemented | safety/support screen |
| Unblock | Implemented | safety/support screen |
| Block history | Implemented | safety/support screen |
| Notification inbox/read/read-all/clear | Implemented | `common/notifications_screen.dart` |
| Shell unread badges | Implemented | caller/listener shells |

## Listener operations

| Capability | Status | Flutter area |
|---|---|---|
| Profile view/edit | Implemented | `listener/listener_profile_screen.dart` |
| Photo/media upload | Implemented | same |
| Categories/languages/rates | Implemented | same |
| Submit verification | Implemented | same |
| Online/offline control | Implemented | dashboard |
| Presence heartbeat | Implemented | dashboard |
| Attendance | Implemented | dashboard |
| Daily online timer | Implemented | dashboard |
| Three-hour target/progress | Implemented | dashboard |
| Missed-day status/policy | Implemented | dashboard |
| Incoming request polling | Implemented | listener shell |
| Caller-nudge notification/banner | Implemented | listener shell |
| Recent sessions | Implemented | dashboard |
| Missed-session callback | Implemented | dashboard/history |
| Listener history search/filter/sort | Implemented | history screen |
| Review list/date filtering | Implemented | reviews screen |
| Public review response | Implemented | reviews screen |
| Weekly availability | Implemented | availability screen |
| Blackout/special availability exceptions | Implemented | availability screen |

## Scheduled/legacy booking source flow

The current React router redirects the old checkout/availability entry points in some places, but the underlying source/API flow still exists. It is included in the Flutter build for completeness.

| Capability | Status | Flutter area |
|---|---|---|
| Query available slots | Legacy/source flow included | `caller/schedule_consultation_screen.dart` |
| Booking agenda/type/duration | Legacy/source flow included | same |
| Create booking | Legacy/source flow included | same |
| Customer booking history | Legacy/source flow included | `caller/caller_history_screen.dart` |
| Cancel booking | Legacy/source flow included | same |
| Create dispute | Legacy/source flow included | same |
| Scheduled call token/status/connect/end | Legacy/source flow included | `session/booking_call_screen.dart` |

## Privacy/governance differences caused by platform APIs

| Web behavior | Mobile equivalent |
|---|---|
| Browser screenshot shortcut interception | Android `FLAG_SECURE` prevents capture when governance enables protection |
| Browser `getDisplayMedia` interception | `FLAG_SECURE`/native window protection |
| Persist browser shortcut interception audit | No reliable Android OS callback exists for every blocked screenshot attempt, so there is no exact event to persist |
| Canvas video processing | Flutter renderer/overlay implementation |
| Web Audio voice effects | Android native audio-effects bridge |
| User/listener call recording helper | Web helper currently returns without recording; mobile likewise does not silently record calls |

## Static verification completed

- All relative Dart imports resolve to files in the project.
- Delimiter/bracket scan reports no unmatched delimiters.
- Every `AppController.api.<method>()` / local `api.<method>()` call found by the parity scan resolves to a method in `ApiService`.
- Backend route paths used by the migration were cross-checked against the uploaded Spring Boot controllers.

## Runtime validation still required

The generator environment does not contain Flutter/Dart/Android SDK tooling, so it cannot truthfully certify a successful APK build or device behavior. On the target Windows PC, run `bootstrap_windows.ps1`, `flutter analyze`, `flutter build apk --debug`, then perform two-account/two-device testing before production release.
