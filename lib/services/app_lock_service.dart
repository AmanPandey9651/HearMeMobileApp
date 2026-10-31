import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLockService extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();
  static const _kLockEnabled = 'app_lock_enabled_pref';
  static const _kPinKey = 'app_lock_secure_pin';

  bool _isUnlocked = false;
  bool _isLockEnabled = false;

  bool get isUnlocked => _isUnlocked;
  bool get isLockEnabled => _isLockEnabled;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isLockEnabled = prefs.getBool(_kLockEnabled) ?? false;
    // If lock is disabled, app starts as unlocked
    if (!_isLockEnabled) {
      _isUnlocked = true;
    } else {
      _isUnlocked = false;
    }
    notifyListeners();
  }

  Future<bool> hasPin() async {
    final pin = await _storage.read(key: _kPinKey);
    return pin != null && pin.trim().length == 4;
  }

  Future<bool> verifyPin(String enteredPin) async {
    final pin = await _storage.read(key: _kPinKey);
    if (pin != null && pin == enteredPin.trim()) {
      _isUnlocked = true;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> setPin(String newPin) async {
    await _storage.write(key: _kPinKey, value: newPin.trim());
    await setLockEnabled(true);
    _isUnlocked = true;
    notifyListeners();
  }

  Future<void> setLockEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLockEnabled, enabled);
    _isLockEnabled = enabled;
    if (!enabled) {
      _isUnlocked = true;
    }
    notifyListeners();
  }

  void lockApp() {
    if (_isLockEnabled) {
      _isUnlocked = false;
      notifyListeners();
    }
  }

  void unlock() {
    _isUnlocked = true;
    notifyListeners();
  }
}
