import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/models.dart';
import '../services/auth_service.dart';

class ApiService {
  final AppConfig  _cfg;
  final AuthService _auth;

  ApiService(this._cfg, this._auth);

  // ── Process audio → extract plates ─────────────────────────────────────────
  Future<List<PlateRow>> processAudio({
    required String filePath,
    required List<GpsPoint> gpsPoints,
    required String recorderName,
    required String sheetName,
  }) async {
    final req = http.MultipartRequest('POST', _cfg.uri('/api/process'));
    req.headers.addAll(_auth.authHeaders);

    final ext  = filePath.endsWith('.wav') ? 'wav' : 'm4a';
    req.files.add(await http.MultipartFile.fromPath('audio', filePath,
        filename: 'recording.$ext'));
    req.fields['gps_data']     = jsonEncode(gpsPoints.map((p) => p.toJson()).toList());
    req.fields['api_key']      = _cfg.apiKey;
    req.fields['model_name']   = _cfg.modelName;
    req.fields['recorder_name'] = recorderName;
    req.fields['sheet_name']   = sheetName.isNotEmpty ? sheetName : 'بيانات المركبات';

    final streamed = await req.send().timeout(const Duration(minutes: 5));
    final res      = await http.Response.fromStream(streamed);

    if (res.statusCode != 200) {
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      throw Exception(j['detail'] ?? 'فشل معالجة الصوت');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes));
    return (j['plates'] as List).map((p) => PlateRow.fromJson(p)).toList();
  }

  // ── Export Excel from rows ─────────────────────────────────────────────────
  Future<List<int>> exportExcel(List<PlateRow> rows, String sheetName, {bool fieldCheck = false}) async {
    final req = http.MultipartRequest(
      'POST',
      _cfg.uri(fieldCheck ? '/api/export-field-check' : '/api/export-excel'),
    );
    req.headers.addAll(_auth.authHeaders);
    req.fields['rows_json']  = jsonEncode(rows.map((r) => r.toJson()).toList());
    req.fields['sheet_name'] = sheetName.isNotEmpty ? sheetName : 'بيانات';

    final streamed = await req.send().timeout(const Duration(minutes: 2));
    final res      = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) throw Exception('فشل تصدير Excel');
    return res.bodyBytes;
  }

  // ── Import Excel → rows ────────────────────────────────────────────────────
  Future<List<PlateRow>> importExcel(String filePath) async {
    final req = http.MultipartRequest('POST', _cfg.uri('/api/parse-excel'));
    req.headers.addAll(_auth.authHeaders);
    req.files.add(await http.MultipartFile.fromPath('file', filePath));

    final streamed = await req.send().timeout(const Duration(minutes: 2));
    final res      = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) {
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      throw Exception(j['detail'] ?? 'فشل استيراد Excel');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes));
    return (j['rows'] as List).map((r) => PlateRow.fromJson(r)).toList();
  }

  // ── Detect column headers in Excel ────────────────────────────────────────
  Future<Map<String, dynamic>> checkHeaders({File? largeFile, File? smallFile, String password = ''}) async {
    final req = http.MultipartRequest('POST', _cfg.uri('/api/check-headers'));
    req.headers.addAll(_auth.authHeaders);
    if (largeFile != null) req.files.add(await http.MultipartFile.fromPath('large_file', largeFile.path));
    if (smallFile != null) req.files.add(await http.MultipartFile.fromPath('small_file', smallFile.path));
    if (password.isNotEmpty) req.fields['password'] = password;

    final streamed = await req.send().timeout(const Duration(minutes: 2));
    final res      = await http.Response.fromStream(streamed);
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  // ── Compare two Excel files ────────────────────────────────────────────────
  Future<List<int>?> checkFiles({
    required File largeFile,
    required File smallFile,
    String password  = '',
    String largeCol  = '',
    String smallCol  = '',
  }) async {
    final req = http.MultipartRequest('POST', _cfg.uri('/api/check'));
    req.headers.addAll(_auth.authHeaders);
    req.files.add(await http.MultipartFile.fromPath('large_file', largeFile.path));
    req.files.add(await http.MultipartFile.fromPath('small_file', smallFile.path));
    if (password.isNotEmpty) req.fields['password'] = password;
    if (largeCol.isNotEmpty) req.fields['large_col'] = largeCol;
    if (smallCol.isNotEmpty) req.fields['small_col'] = smallCol;

    final streamed = await req.send().timeout(const Duration(minutes: 3));
    final res      = await http.Response.fromStream(streamed);

    final ct = res.headers['content-type'] ?? '';
    if (ct.contains('spreadsheetml')) return res.bodyBytes;

    final j = jsonDecode(utf8.decode(res.bodyBytes));
    throw Exception(j['detail'] ?? 'لا توجد تطابقات');
  }

  // ── Parse reference plates from Excel ─────────────────────────────────────
  Future<List<String>> parseRefPlates(String filePath, {String col = ''}) async {
    final req = http.MultipartRequest('POST', _cfg.uri('/api/parse-ref-plates'));
    req.headers.addAll(_auth.authHeaders);
    req.files.add(await http.MultipartFile.fromPath('file', filePath));
    if (col.isNotEmpty) req.fields['col'] = col;

    final streamed = await req.send().timeout(const Duration(minutes: 2));
    final res      = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) {
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      throw Exception(j['detail'] ?? 'فشل قراءة الملف المرجعي');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes));
    return (j['plates'] as List).map((p) => p.toString()).toList();
  }

  // ── Check single plate against reference ──────────────────────────────────
  Future<bool> checkRefPlate(String filePath, String plate, {String col = ''}) async {
    final req = http.MultipartRequest('POST', _cfg.uri('/api/check-ref-plate'));
    req.headers.addAll(_auth.authHeaders);
    req.files.add(await http.MultipartFile.fromPath('file', filePath));
    req.fields['plate'] = plate;
    if (col.isNotEmpty) req.fields['col'] = col;

    final streamed = await req.send().timeout(const Duration(minutes: 1));
    final res      = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) throw Exception('فشل فحص اللوحة');
    final j = jsonDecode(utf8.decode(res.bodyBytes));
    return j['exists'] == true;
  }

  // ── Parse GPS points from Excel ────────────────────────────────────────────
  Future<Map<String, dynamic>> parseGpsExcel(String filePath, {String gpsCol = 'GPS', List<String> labelCols = const []}) async {
    final req = http.MultipartRequest('POST', _cfg.uri('/api/parse-gps-excel'));
    req.headers.addAll(_auth.authHeaders);
    req.files.add(await http.MultipartFile.fromPath('file', filePath));
    req.fields['gps_col'] = gpsCol;
    if (labelCols.isNotEmpty) req.fields['label_cols_json'] = jsonEncode(labelCols);

    final streamed = await req.send().timeout(const Duration(minutes: 2));
    final res      = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) throw Exception('فشل قراءة ملف GPS');
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  // ── Admin: list users ──────────────────────────────────────────────────────
  Future<List<dynamic>> adminGetUsers() async {
    final res = await _auth.authGet(_cfg.uri('/admin/users'));
    if (res.statusCode != 200) throw Exception('فشل تحميل المستخدمين');
    return jsonDecode(utf8.decode(res.bodyBytes)) as List;
  }

  Future<void> adminCreateUser(String username, String password, bool isAdmin) async {
    final res = await http.post(
      _cfg.uri('/admin/users'),
      headers: {..._auth.authHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password, 'is_admin': isAdmin}),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      throw Exception(j['detail'] ?? 'فشل إنشاء المستخدم');
    }
  }

  Future<void> adminSetActive(int id, bool active) async {
    final res = await http.patch(
      _cfg.uri('/admin/users/$id'),
      headers: {..._auth.authHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({'is_active': active}),
    );
    if (res.statusCode != 200) throw Exception('فشل تحديث الحساب');
  }

  Future<void> adminResetDevice(int id) async {
    final res = await http.post(
      _cfg.uri('/admin/users/$id/reset-device'),
      headers: _auth.authHeaders,
    );
    if (res.statusCode != 200) throw Exception('فشل مسح الجهاز');
  }

  Future<void> adminDeleteUser(int id) async {
    final res = await http.delete(
      _cfg.uri('/admin/users/$id'),
      headers: _auth.authHeaders,
    );
    if (res.statusCode != 200) throw Exception('فشل حذف المستخدم');
  }
}
