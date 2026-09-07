import 'package:flutter/material.dart';
import 'api_client.dart';

class AuthProvider extends ChangeNotifier {
  final ApiClient api;
  Session? session;
  bool loading = true;
  bool restoreError = false;

  AuthProvider(this.api) {
    _restore();
  }

  Future<void> _restore() async {
    await api.loadToken();
    if (api.token != null) {
      restoreError = false;
      try {
        session = await api.me();
      } on ApiException catch (e) {
        if (e.status == 401) {
          await api.setToken(null);
        } else {
          restoreError = true;
        }
      } catch (_) {
        restoreError = true;
      }
    }
    loading = false;
    notifyListeners();
  }

  Future<void> retryRestore() async {
    loading = true;
    notifyListeners();
    await _restore();
  }

  Future<void> login(String email, String password) async {
    final s = await api.login(email, password);
    if (!s.isProvider) {
      throw ApiException('Doctor Console is for doctors and clinic staff only.', 403);
    }
    await api.setToken(s.token);
    session = s;
    notifyListeners();
  }

  Future<void> logout() async {
    await api.setToken(null);
    session = null;
    notifyListeners();
  }

  bool get isLoggedIn => session != null;
}
