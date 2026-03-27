import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppConfig extends ChangeNotifier {
  static const _keyBackendUrl  = 'backend_url';
  static const _keyApiKey      = 'api_key';
  static const _keyModelTab    = 'model_tab';
  static const _keyModelManual = 'model_manual';
  static const _keyOrsKey      = 'ors_key';
  static const _keyGoogleMaps  = 'google_maps_key';

  static const Map<int, String> modelMap = {
    1: 'gemini-2.5-flash',
    2: 'gemini-3-flash-preview',
  };

  String backendUrl  = 'https://YOUR-APP.railway.app';
  String apiKey      = '';
  int    modelTab    = 1;
  String modelManual = '';
  String orsKey      = '';
  String googleMapsKey = '';

  String get modelName {
    if (modelTab == 3) return modelManual.isNotEmpty ? modelManual : 'gemini-2.5-flash';
    return modelMap[modelTab] ?? 'gemini-2.5-flash';
  }

  bool get hasApiKey => apiKey.length > 5;
  bool get hasBackend => backendUrl.startsWith('http');

  Uri uri(String path) => Uri.parse('$backendUrl$path');

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    backendUrl   = prefs.getString(_keyBackendUrl)  ?? 'https://YOUR-APP.railway.app';
    apiKey       = prefs.getString(_keyApiKey)      ?? '';
    modelTab     = prefs.getInt(_keyModelTab)       ?? 1;
    modelManual  = prefs.getString(_keyModelManual) ?? '';
    orsKey       = prefs.getString(_keyOrsKey)      ?? '';
    googleMapsKey = prefs.getString(_keyGoogleMaps) ?? '';
    notifyListeners();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBackendUrl,  backendUrl);
    await prefs.setString(_keyApiKey,      apiKey);
    await prefs.setInt(_keyModelTab,       modelTab);
    await prefs.setString(_keyModelManual, modelManual);
    await prefs.setString(_keyOrsKey,      orsKey);
    await prefs.setString(_keyGoogleMaps,  googleMapsKey);
    notifyListeners();
  }

  void update({
    String? url,
    String? key,
    int?    tab,
    String? manual,
    String? ors,
    String? gmaps,
  }) {
    if (url    != null) backendUrl    = url;
    if (key    != null) apiKey        = key;
    if (tab    != null) modelTab      = tab;
    if (manual != null) modelManual   = manual;
    if (ors    != null) orsKey        = ors;
    if (gmaps  != null) googleMapsKey = gmaps;
    notifyListeners();
  }
}
