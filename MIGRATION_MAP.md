# Web → Flutter migration map (caller/user + listener)

| React/web source area | Flutter mobile implementation |
|---|---|
| `HomePage` | `lib/screens/caller/caller_home_screen.dart` |
| `ExpertsSearchPage` | `lib/screens/caller/caller_home_screen.dart` |
| `ExpertProfilePage` | `lib/screens/caller/listener_detail_screen.dart` |
| Follow/favourites + online listener data | `caller_home_screen.dart`, `followed_listeners_screen.dart`, `listener_detail_screen.dart` |
| Anonymous caller profile controls | `lib/screens/caller/anonymous_profile_screen.dart` |
| `WalletPage` / `RechargeModal` | `lib/screens/caller/wallet_screen.dart` |
| `CustomerBookingsPage` instant-session history | `lib/screens/caller/caller_history_screen.dart` |
| `CustomerBookingsPage` legacy bookings/disputes | `caller_history_screen.dart`, `schedule_consultation_screen.dart`, `session/booking_call_screen.dart` |
| `BookingCheckoutPage` | `lib/screens/caller/schedule_consultation_screen.dart` |
| Caller callback invitation | `lib/screens/caller/caller_shell.dart` |
| `HowItWorksPage` | `lib/screens/common/how_it_works_screen.dart` |
| `ConsultationCallPage` | `lib/screens/session/session_screen.dart` |
| WebRTC signals / ICE / reconnect | `session_screen.dart` + `lib/services/api_service.dart` |
| In-call chat | `session_screen.dart` |
| `InCallGiftingModal` | gift sheet in `session_screen.dart` |
| Icebreaker prompt/broadcast | topic sheet in `session_screen.dart` |
| `InCallMiniGamesModal` | `lib/widgets/in_call_mini_games.dart` + `session_screen.dart` signaling |
| Web video masks/filters | `lib/widgets/video_privacy_filter.dart` + `session_screen.dart` |
| Web voice filters | `lib/services/android_voice_fx.dart` + native bridge written by `bootstrap_windows.ps1` |
| `NotificationDropdown` | `lib/screens/common/notifications_screen.dart` + shell unread badges |
| Safety/blocking/inquiries | `lib/screens/common/safety_support_screen.dart` |
| `AntiCaptureGuard` | backend recording-governance polling + Android `FLAG_SECURE` in `AppController`/bootstrap native bridge |
| Web inactivity logout hook | `lib/core/inactivity_guard.dart` |
| Web protected-session watcher | five-second watcher in `lib/core/app_controller.dart` |
| Caller `LoginPage` / OTP / Google | `lib/screens/auth/login_screen.dart` |
| Listener login/forgot/reset | `lib/screens/auth/login_screen.dart` |
| `RegisterPage` listener onboarding | `lib/screens/auth/listener_register_screen.dart` |
| `ExpertDashboardPage` | `lib/screens/listener/listener_dashboard_screen.dart` |
| `ListenerActivity` attendance/target/callback | `listener_dashboard_screen.dart`, `listener_history_screen.dart` |
| `IncomingCallModal` | `lib/screens/listener/listener_shell.dart` |
| Listener nudge banner | `listener_shell.dart` notification polling/dialog |
| `ListenerProfilePage` | `lib/screens/listener/listener_profile_screen.dart` |
| Expert/listener availability rules | `lib/screens/listener/availability_screen.dart` |
| Listener session ledger | `lib/screens/listener/listener_history_screen.dart` |
| Listener earnings + payouts | `lib/screens/listener/listener_earnings_screen.dart` |
| Listener reviews/responses | `lib/screens/listener/listener_reviews_screen.dart` |
| Account menus | `lib/screens/common/account_menu_screen.dart`, caller/listener More screens |

## Deliberate exclusions

Admin and super-admin screens/actions are not included because the requested mobile scope is caller/user + listener only.

## Platform-specific equivalence

The browser anti-capture keyboard audit has no exact Android API equivalent. Android blocks capture with `FLAG_SECURE` according to backend governance. Browser Web Audio/Canvas media processing is represented by the Flutter/native Android media implementation rather than copied JavaScript.
