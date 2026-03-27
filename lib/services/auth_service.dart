import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

class AuthService extends ChangeNotifier {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final AppConfig _config;

  String _accessToken  = '';
  String _refreshToken = '';
  bool   _isAdmin      = false;
  bool   _loggedIn     = false;

  AuthService(this._config);

  bool get isLoggedIn => _loggedIn;
  bool get isAdmin    => _isAdmin;
  String get token    => _accessToken;

  // ── Auto-login from stored tokens ───────────────────────────────────────────
  Future<void> tryAutoLogin() async {
    try {
      _accessToken  = await _storage.read(key: 'access_token')  ?? '';
      _refreshToken = await _storage.read(key: 'refresh_token') ?? '';
      final admin   = await _storage.read(key: 'is_admin')      ?? '0';
      _isAdmin      = admin == '1';
      if (_accessToken.isNotEmpty) {
        _loggedIn = true;
        notifyListeners();
      }
    } catch (_) {}
  }

  // ── Login ──────────────────────────────────────────────────────────────────
  Future<String?> login(String username, String password, String deviceId) async {
    try {
      final res = await http.post(
        _config.uri('/auth/login'),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-Id': deviceId,
        },
        body: jsonEncode({'username': username, 'password': password}),
      ).timeout(const Duration(seconds: 15));

      final j = jsonDecode(utf8.decode(res.bodyBytes));

      if (res.statusCode == 200) {
        await _saveTokens(j['access_token'], j['refresh_token'], j['is_admin'] == true);
        _loggedIn = true;
        notifyListeners();
        return null; // success
      }

      return _errorMsg(res.statusCode, j);
    } catch (e) {
      return 'تعذر الاتصال بالخادم — تحقق من الرابط أو الشبكة';
    }
  }

  // ── Refresh ────────────────────────────────────────────────────────────────
  Future<bool> refresh() async {
    if (_refreshToken.isEmpty) return false;
    try {
      final res = await http.post(
        _config.uri('/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': _refreshToken}),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final j = jsonDecode(utf8.decode(res.bodyBytes));
        await _saveTokens(j['access_token'], j['refresh_token'], j['is_admin'] == true);
        return true;
      }
    } catch (_) {}
    return false;
  }

  // ── Logout ─────────────────────────────────────────────────────────────────
  Future<void> logout() async {
    _accessToken  = '';
    _refreshToken = '';
    _isAdmin      = false;
    _loggedIn     = false;
    await _storage.deleteAll();
    notifyListeners();
  }

  // ── Authenticated HTTP request (auto-refresh on 401) ───────────────────────
  Future<http.Response> authGet(Uri uri) async {
    var res = await http.get(uri, headers: _authHeaders());
    if (res.statusCode == 401) {
      if (await refresh()) res = await http.get(uri, headers: _authHeaders());
      else { await logout(); throw Exception('انتهت الجلسة'); }
    }
    return res;
  }

  Future<http.StreamedResponse> authSend(http.BaseRequest req) async {
    req.headers.addAll(_authHeaders());
    var res = await req.send();
    if (res.statusCode == 401) {
      if (await refresh()) {
        // Rebuild request (BaseRequest can't be resent)
        throw Exception('RETRY');
      } else {
        await logout();
        throw Exception('انتهت الجلسة');
      }
    }
    return res;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Map<String, String> get authHeaders => _authHeaders();

  Map<String, String> _authHeaders() =>
      {'Authorization': 'Bearer $_accessToken'};

  Future<void> _saveTokens(String at, String rt, bool admin) async {
    _accessToken  = at;
    _refreshToken = rt;
    _isAdmin      = admin;
    await _storage.write(key: 'access_token',  value: at);
    await _storage.write(key: 'refresh_token', value: rt);
    await _storage.write(key: 'is_admin',      value: admin ? '1' : '0');
  }

  String _errorMsg(int status, dynamic j) {
    final detail = j is Map ? (j['detail'] ?? '') : '';
    if (status == 401) return 'اسم المستخدم أو كلمة المرور غير صحيحة';
    if (status == 403) {
      if (detail.toString().contains('disabled')) return 'هذا الحساب معطّل';
      if (detail.toString().contains('device'))   return 'هذا الحساب مربوط بجهاز آخر';
    }
    return detail.toString().isNotEmpty ? detail.toString() : 'فشل تسجيل الدخول';
  }
}
