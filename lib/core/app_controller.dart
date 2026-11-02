import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/app_models.dart';
import '../services/api_service.dart';
import '../services/android_voice_fx.dart';
import 'api_client.dart';
import 'app_config.dart';

class GoogleSignInException implements Exception {
  final String message;
  final bool isDeveloperError;
  final Object? originalError;

  GoogleSignInException({
    required this.message,
    this.isDeveloperError = false,
    this.originalError,
  });

  @override
  String toString() => message;
}

class AppController extends ChangeNotifier {
  static const _tokenKey = 'talkstrangers_access_token';
  static const _userKey = 'talkstrangers_user';
  static const _expertProfileKey = 'talkstrangers_expert_profile';
  static const _authGovernanceKey = 'talkstrangers_auth_governance';
  static const _brandGovernanceKey = 'talkstrangers_brand_governance';
  String brandTheme = 'FEELBACK';
  String brandName = 'FeelBack';

  bool get isFeelBack => true;
  String get activeBrandName => 'FeelBack';
  String get headerLogoAsset => 'assets/images/feelback-logo.png';
  String get splashLogoAsset => 'assets/images/feelback-logo-white.png';
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  final ApiClient client = ApiClient();
  late final ApiService api = ApiService(client);

  AppUser? user;
  Map<String, dynamic>? expertProfile;
  bool loading = true;
  bool showAuthSplash = false;
  bool isResolvingListenerStatus = false;

  void finishAuthSplash() {
    showAuthSplash = false;
    notifyListeners();
  }
  String? lastError;
  RecordingGovernanceModel? recordingGovernance;
  bool phoneLoginEnabled = false;
  bool googleLoginEnabled = true;
  int userInactivityMinutes = 30;
  int listenerInactivityMinutes = 30;
  int adminInactivityMinutes = 15;
  int mobileInactivityDays = 30;
  Timer? _governanceTimer;
  Timer? _accountStatusTimer;
  bool _checkingAccountStatus = false;
  int activeSessionCount = 0;
  num referralRewardAmount = 20;

  bool get isListenerVerified {
    if (user == null || !user!.isListener) return false;
    final status = '${expertProfile?['status'] ?? ''}'.toUpperCase();
    if (status == 'VERIFIED') return true;
    if (status == 'SUBMITTED' || status == 'REJECTED' || status == 'SUSPENDED') return false;
    // An active listener whose account is approved on the backend is verified
    return user!.status.toUpperCase() == 'ACTIVE';
  }

  AppController() {
    client.onUnauthorized = () => logout(markOffline: false);
  }

  Future<void> reconnectBackend() async {
    loading = true;
    notifyListeners();
    await bootstrap();
  }

  Future<void> bootstrap() async {
    try {
      await PrivacyPlatform.setSecure(false);
      final savedAuth = await _storage.read(key: _authGovernanceKey);
      final savedBrand = await _storage.read(key: _brandGovernanceKey);
      if (savedBrand != null) {
        try {
          final parsed = jsonDecode(savedBrand);
          brandTheme = 'FEELBACK';
          brandName = 'FeelBack';
        } catch (_) {}
      }
      if (savedAuth != null) {
        try {
          final parsed = jsonDecode(savedAuth);
          phoneLoginEnabled = parsed['phoneLoginEnabled'] == true;
          googleLoginEnabled = parsed['googleLoginEnabled'] != false;
        } catch (_) {}
      }
      await Future.wait([refreshGovernance(), refreshAuthGovernance(), refreshInactivityGovernance(), refreshBrandGovernance()]);
      _governanceTimer ??= Timer.periodic(const Duration(seconds: 10), (_) {
        refreshGovernance();
        refreshBrandGovernance();
      });
      final token = await _storage.read(key: _tokenKey);
      final savedUser = await _storage.read(key: _userKey);
      final savedExpert = await _storage.read(key: _expertProfileKey);
      client.token = token;
      if (savedUser != null) user = AppUser.fromJson(Map<String, dynamic>.from(jsonDecode(savedUser)));
      if (savedExpert != null) {
        try {
          expertProfile = Map<String, dynamic>.from(jsonDecode(savedExpert));
        } catch (_) {}
      }
      if (token != null) {
        try {
          user = await api.me();
          if (user != null && user!.isListener) {
            try {
              expertProfile = await api.myExpertProfile();
            } catch (_) {
              if (user!.status.toUpperCase() == 'ACTIVE') {
                expertProfile ??= {'status': 'VERIFIED'};
              }
            }
          }
          await _persist();
          _startAccountWatcher();
        } catch (_) {
          await logout(markOffline: false);
        }
      }
    } catch (e, stack) {
      debugPrint('[AppController] Bootstrap exception (recovered): $e\n$stack');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _applyAuth(Map<String, dynamic> auth) async {
    isResolvingListenerStatus = true;
    showAuthSplash = true;
    notifyListeners();
    try {
      final token = '${auth['accessToken'] ?? ''}';
      if (token.isEmpty) throw ApiException(500, 'Backend did not return an access token');
      client.token = token;
      final parsedUser = AppUser.fromJson(Map<String, dynamic>.from(auth['user'] as Map));
      user = parsedUser;
      if (parsedUser.isListener) {
        try {
          expertProfile = await api.myExpertProfile();
        } catch (_) {
          if (parsedUser.status.toUpperCase() == 'ACTIVE') {
            expertProfile = {'status': 'VERIFIED'};
          } else {
            expertProfile = {'status': 'SUBMITTED'};
          }
        }
      } else {
        expertProfile = null;
      }
      await _persist();
      _startAccountWatcher();
    } catch (e, stack) {
      debugPrint('[AppController] Bootstrap exception (recovered): $e\n$stack');
    } finally {
      isResolvingListenerStatus = false;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    if (client.token != null) await _storage.write(key: _tokenKey, value: client.token);
    if (user != null) await _storage.write(key: _userKey, value: jsonEncode(user!.toJson()));
    if (expertProfile != null) {
      await _storage.write(key: _expertProfileKey, value: jsonEncode(expertProfile));
    } else {
      await _storage.delete(key: _expertProfileKey);
    }
  }

  Future<void> login(String email, String password) async => _applyAuth(await api.login(email, password));
  Future<void> verifyOtp(String mobile, String otp) async => _applyAuth(await api.verifyOtp(mobile, otp));
  Future<void> firebaseOtpLogin(String idToken, [String? mobileNumber]) async => _applyAuth(await api.firebaseOtpLogin(idToken, mobileNumber));
  Future<void> registerListener(Map<String, dynamic> data) async => _applyAuth(await api.registerListener(data));

  Future<void> googleLogin() async {
    final serverClientId = AppConfig.googleServerClientId.trim();
    final signIn = GoogleSignIn(
      clientId: defaultTargetPlatform == TargetPlatform.iOS
          ? '972145849986-7afvc49iq0b6nu55a74qht473atgaaq3.apps.googleusercontent.com'
          : null,
      serverClientId: serverClientId.isEmpty ? null : serverClientId,
    );
    try {
      final account = await signIn.signIn();
      if (account == null) return;
      final auth = await account.authentication;
      if (auth.idToken == null) throw ApiException(400, 'Google did not return an ID token. Configure GOOGLE_SERVER_CLIENT_ID.');
      await _applyAuth(await api.googleLogin(auth.idToken!));
    } catch (e) {
      final err = e.toString();
      if (err.contains('10') || err.contains('ApiException: 10') || err.contains('DEVELOPER_ERROR')) {
        throw GoogleSignInException(
          message: 'Google Sign-In configuration error (ApiException: 10).\nYour debug SHA-1 fingerprint needs to be registered in Google Cloud Console for com.harto.feelback.',
          isDeveloperError: true,
          originalError: e,
        );
      }
      rethrow;
    }
  }

  Future<void> devGoogleLogin() async {
    await _applyAuth(await api.googleLogin('test_google_token'));
  }

  void updatePresence(String nextPresence) {
    if (expertProfile != null) {
      expertProfile = Map<String, dynamic>.from(expertProfile!);
      expertProfile!['presence'] = nextPresence;
      expertProfile!['presenceStatus'] = nextPresence;
      notifyListeners();
    }
  }

  Future<void> refreshExpertProfile() async {
    if (user != null && user!.isListener) {
      try {
        final p = await api.myExpertProfile();
        expertProfile = p;
        notifyListeners();
      } catch (_) {}
    }
  }

  Future<void> refreshReferralReward() async {
    if (client.token == null) return;
    try {
      final summary = await api.getReferralSummary();
      final potential = summary['potentialRewardPerReferral'];
      if (potential != null) {
        final val = potential is num ? potential : num.tryParse(potential.toString());
        if (val != null && val > 0) {
          referralRewardAmount = val;
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  Future<void> refreshUser() async {
    user = await api.me();
    if (user != null && user!.isListener) {
      try {
        expertProfile = await api.myExpertProfile();
      } catch (_) {
        if (user!.status.toUpperCase() == 'ACTIVE') {
          expertProfile ??= {'status': 'VERIFIED'};
        }
      }
    }
    await _persist();
    notifyListeners();
    refreshReferralReward();
  }

  void _startAccountWatcher() {
    _accountStatusTimer?.cancel();
    if (client.token == null || user == null) return;
    // Mirrors the web client's protected-session watcher: re-check the account
    // frequently so suspension, token expiry, or role changes are reflected
    // without requiring an app restart.
    _accountStatusTimer = Timer.periodic(const Duration(seconds: 5), (_) => _verifyAccountStatus());
  }

  Future<void> _verifyAccountStatus() async {
    if (_checkingAccountStatus || client.token == null || user == null) return;
    _checkingAccountStatus = true;
    try {
      final latest = await api.me();
      final userChanged = latest.encode() != user!.encode();
      user = latest;
      var expertChanged = false;
      if (user != null && user!.isListener) {
        try {
          final p = await api.myExpertProfile();
          if ('${p['status']}' != '${expertProfile?['status']}' ||
              '${p['presence'] ?? p['presenceStatus']}' != '${expertProfile?['presence'] ?? expertProfile?['presenceStatus']}' ||
              '${p['activeSessionType']}' != '${expertProfile?['activeSessionType']}' ||
              '${p['ratingAvg']}' != '${expertProfile?['ratingAvg']}' ||
              '${p['reviewCount']}' != '${expertProfile?['reviewCount']}') {
            expertProfile = p;
            expertChanged = true;
          }
        } catch (_) {}
      }
      await _persist();
      if (userChanged || expertChanged) notifyListeners();
    } catch (_) {
      // ApiClient handles HTTP 401 by invoking onUnauthorized. Other temporary
      // network failures should not destroy a valid local session.
    } finally {
      _checkingAccountStatus = false;
    }
  }

  Future<void> refreshGovernance() async {
    try {
      final settings = await api.recordingGovernance();
      recordingGovernance = settings;
      final shouldSecure = !kDebugMode && (settings.blockScreenshotsEnabled || settings.blockScreenRecordingEnabled);
      await PrivacyPlatform.setSecure(shouldSecure);
    } catch (_) {
      await PrivacyPlatform.setSecure(false);
    }
  }

  Future<void> refreshBrandGovernance() async {
    try {
      final settings = await api.brandGovernance();
      final nextTheme = 'FEELBACK';
      final nextName = 'FeelBack';
      if (nextTheme != brandTheme || nextName != brandName) {
        brandTheme = nextTheme;
        brandName = nextName;
        await _storage.write(
          key: _brandGovernanceKey,
          value: jsonEncode({'brandTheme': brandTheme, 'brandName': brandName}),
        );
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> refreshAuthGovernance() async {
    try {
      final settings = await api.authGovernance();
      phoneLoginEnabled = settings['phoneLoginEnabled'] == true ||
          (settings['phoneLoginEnabled'] != false && '${settings['phoneLoginEnabled']}'.toLowerCase() != 'false');
      googleLoginEnabled = settings['googleLoginEnabled'] != false && '${settings['googleLoginEnabled']}'.toLowerCase() != 'false';
      await _storage.write(
        key: _authGovernanceKey,
        value: jsonEncode({'phoneLoginEnabled': phoneLoginEnabled, 'googleLoginEnabled': googleLoginEnabled}),
      );
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshInactivityGovernance() async {
    try {
      final settings = await api.inactivityGovernance();
      userInactivityMinutes = (settings['userInactivityMinutes'] as num?)?.toInt() ?? 30;
      listenerInactivityMinutes = (settings['listenerInactivityMinutes'] as num?)?.toInt() ?? 30;
      adminInactivityMinutes = (settings['adminInactivityMinutes'] as num?)?.toInt() ?? 15;
      mobileInactivityDays = (settings['mobileInactivityDays'] as num?)?.toInt() ?? 30;
      notifyListeners();
    } catch (_) {}
  }

  void enterActiveSession() {
    activeSessionCount++;
    notifyListeners();
  }

  void exitActiveSession() {
    if (activeSessionCount > 0) activeSessionCount--;
    notifyListeners();
  }

  @override
  void dispose() {
    _governanceTimer?.cancel();
    _accountStatusTimer?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>> completeOnboarding({
    required bool acceptTerms,
    String? referralCode,
  }) async {
    try {
      final res = await api.completeOnboarding(
        acceptTerms: acceptTerms,
        referralCode: referralCode,
      );
      if (res['user'] != null && res['user'] is Map) {
        user = AppUser.fromJson(Map<String, dynamic>.from(res['user'] as Map));
        await _storage.write(key: _userKey, value: user!.encode());
        notifyListeners();
      }
      return res;
    } catch (e) {
      lastError = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> logout({bool markOffline = true}) async {
    await PrivacyPlatform.setSecure(false);
    if (markOffline && user?.isListener == true && client.token != null) {
      try { await api.updatePresence('OFFLINE'); } catch (_) {}
    }
    _accountStatusTimer?.cancel();
    _accountStatusTimer = null;
    client.token = null;
    user = null;
    expertProfile = null;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
    await _storage.delete(key: _expertProfileKey);
    // Show splash AFTER logout completes
    showAuthSplash = true;
    notifyListeners();
  }
}
