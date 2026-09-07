import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

const _biometricPrefKey = 'careloop_biometric_enabled';
const _pinHashPrefKey = 'careloop_pin_hash';

class AuthProvider extends ChangeNotifier {
  final ApiClient api;
  final LocalAuthentication _localAuth = LocalAuthentication();
  Session? session;
  bool loading = true;

  /// True once a stored session was restored but hasn't been unlocked with biometrics yet —
  /// the UI shows a lock screen instead of the app until this clears.
  bool locked = false;

  /// Whether the user has opted in to biometric unlock (persisted).
  bool biometricEnabled = false;

  /// Whether this device actually has usable biometric hardware/enrollment right now.
  bool biometricAvailable = false;

  /// Set whenever a biometric check/prompt fails, with the real platform reason — surfaced in
  /// the UI instead of failing silently, since "nothing happened" is undiagnosable on its own.
  String? biometricError;

  /// Hashed 6-digit PIN, if the user has set one (null = no PIN configured). Like biometrics,
  /// this is a LOCAL re-entry gate on top of an already-cached, server-issued session token — not
  /// a server-side credential, so it (like biometricEnabled) can only ever apply to the lock
  /// screen for a session that already exists, never the very first email/password login.
  String? _pinHash;
  bool get pinEnabled => _pinHash != null;

  /// True for one HomeShell build right after a fresh password login — that's when the
  /// biometric opt-in prompt should fire (see main.dart). Not set on session restore/unlock, only
  /// on an actual login() call, so returning users aren't asked again every launch.
  bool justLoggedIn = false;

  /// Set when a cached token exists but re-verifying it at startup failed for a reason that is
  /// NOT "the server rejected this token" — a dropped connection, a timeout, the dev tunnel being
  /// mid-restart, etc. The token is deliberately kept in this case (see _restore): only a genuine
  /// 401 from the server means the session is actually gone.
  bool restoreError = false;

  void clearJustLoggedIn() {
    justLoggedIn = false;
  }

  AuthProvider(this.api) {
    _restore();
  }

  Future<void> _restore() async {
    await api.loadToken();
    final prefs = await SharedPreferences.getInstance();
    biometricEnabled = prefs.getBool(_biometricPrefKey) ?? false;
    _pinHash = prefs.getString(_pinHashPrefKey);
    biometricAvailable = await _checkBiometricAvailable();
    if (api.token != null) {
      restoreError = false;
      try {
        session = await api.me();
        // A valid cached session behind biometric/PIN lock — the token itself already proves who
        // this is server-side; biometrics/PIN here just gate re-opening the app on this device.
        locked = (biometricEnabled && biometricAvailable) || pinEnabled;
      } on ApiException catch (e) {
        if (e.status == 401) {
          // The server itself rejected this token — actually logged out, not just unreachable.
          await api.setToken(null);
        } else {
          restoreError = true; // 5xx etc. — leave the token alone, let the user retry.
        }
      } catch (_) {
        // Network/connectivity failure (unreachable server, timeout, dropped tunnel...) — not
        // proof the token is invalid, so don't discard a PIN/biometric-protected session over it.
        restoreError = true;
      }
    }
    loading = false;
    notifyListeners();
  }

  /// Re-runs the startup session check — offered to the user after a restoreError instead of
  /// silently leaving them stuck, or (the old behavior) having already thrown their session away.
  Future<void> retryRestore() async {
    loading = true;
    notifyListeners();
    await _restore();
  }

  Future<bool> _checkBiometricAvailable() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!supported || !canCheck) {
        biometricError = !supported
            ? 'This device reports no biometric support.'
            : 'No fingerprint or face is enrolled on this device yet — set one up in the phone\'s '
                'Settings > Security first, then it can be used here.';
      }
      return supported && canCheck;
    } catch (e) {
      biometricError = 'Could not check biometric availability: $e';
      return false; // no biometric plugin support on this device/emulator — fail closed, not locked
    }
  }

  Future<void> setBiometricEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricPrefKey, value);
    biometricEnabled = value;
    notifyListeners();
  }

  /// Prompts the device's fingerprint/face unlock. Returns whether it succeeded; on failure,
  /// `biometricError` carries the actual platform reason for the caller to show.
  Future<bool> unlockWithBiometrics() async {
    biometricError = null;
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: 'Unlock HealthFolio',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      if (ok) {
        locked = false;
      } else {
        biometricError = 'Not confirmed.';
      }
      notifyListeners();
      return ok;
    } catch (e) {
      biometricError = '$e';
      notifyListeners();
      return false;
    }
  }

  // Local-only PIN hash — not a security boundary against someone with access to the device's
  // storage, same threat model as any app-level PIN gate (Signal, banking apps' quick-unlock,
  // etc.); it just needs to not be reversible from a casual read of shared_preferences.
  String _hashPin(String pin) => sha256.convert(utf8.encode('careloop_pin_v1:$pin')).toString();

  Future<void> setPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final hash = _hashPin(pin);
    await prefs.setString(_pinHashPrefKey, hash);
    _pinHash = hash;
    notifyListeners();
  }

  Future<void> clearPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pinHashPrefKey);
    _pinHash = null;
    notifyListeners();
  }

  bool unlockWithPin(String pin) {
    final ok = _pinHash != null && _hashPin(pin) == _pinHash;
    if (ok) {
      locked = false;
      notifyListeners();
    }
    return ok;
  }

  Future<void> login(String email, String password) async {
    final s = await api.login(email, password);
    await api.setToken(s.token);
    session = s;
    locked = false;
    justLoggedIn = true;
    notifyListeners();
  }

  Future<void> logout() async {
    await api.setToken(null);
    session = null;
    locked = false;
    notifyListeners();
  }

  /// What "Log out" in the app menu actually does now: if a PIN or biometric unlock is set up,
  /// this just re-locks the app (session/token stay cached) so the next open lands on the PIN/
  /// Face ID screen instead of a fresh password login. Falls back to a real logout() when neither
  /// is configured, since there'd be no way back in otherwise. A true full sign-out (to switch to
  /// a different account) is still logout() directly — see BiometricLockScreen's "Use another
  /// account".
  Future<void> lock() async {
    if ((biometricEnabled && biometricAvailable) || pinEnabled) {
      locked = true;
      notifyListeners();
    } else {
      await logout();
    }
  }
}
