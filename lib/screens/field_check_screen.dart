import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';

class FieldCheckScreen extends StatefulWidget {
  const FieldCheckScreen({super.key});

  @override
  State<FieldCheckScreen> createState() => _FieldCheckScreenState();
}

class _FieldCheckScreenState extends State<FieldCheckScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // ── Controllers ────────────────────────────────────────────────────────────
  final _recorderNameCtrl = TextEditingController();
  final _sheetNameCtrl    = TextEditingController(text: 'التشيك الميداني');
  final _singlePlateCtrl  = TextEditingController();

  // ── Reference file ─────────────────────────────────────────────────────────
  String?       _refFilePath;
  String        _refFileName = '';
  List<String>  _refHeaders  = [];
  String        _refDetectedCol = '';
  String        _refColBadge = '—';
  bool          _refLoading  = false;

  // ── Recording ──────────────────────────────────────────────────────────────
  final _recorder = AudioRecorder();
  bool   _isRecording = false;
  bool   _hasStopped  = false;
  String? _recordedPath;
  int    _recSecs     = 0;
  Timer? _recTimer;

  List<GpsPoint> _gpsPoints   = [];
  Timer? _autoGpsTimer;
  bool   _autoGpsMode = true;
  int    _gpsInterval = 5;
  String _gpsStatus   = 'في انتظار التسجيل';
  bool   _gpsActive   = false;

  // ── Results ────────────────────────────────────────────────────────────────
  List<PlateRow> _allRows     = [];
  List<PlateRow> _matchedRows = [];
  String?        _originGps;   // midpoint GPS from last recording (for maps links)

  // ── Single plate lookup ────────────────────────────────────────────────────
  String _singlePlateResult = '';
  bool   _singlePlateOk     = false;
  bool   _singlePlateChecking = false;

  // ── Status ─────────────────────────────────────────────────────────────────
  StatusType _sType = StatusType.info;
  String     _sMsg  = '';
  bool       _processing = false;

  static const int _maxSecs = 300;

  @override
  void initState() {
    super.initState();
    _loadPersistedData();
  }

  @override
  void dispose() {
    _recTimer?.cancel();
    _autoGpsTimer?.cancel();
    _recorder.dispose();
    _recorderNameCtrl.dispose();
    _sheetNameCtrl.dispose();
    _singlePlateCtrl.dispose();
    super.dispose();
  }

  // ── Reference file ─────────────────────────────────────────────────────────
  Future<void> _pickRefFile() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls']);
    if (r == null || r.files.single.path == null) return;
    setState(() {
      _refFilePath  = r.files.single.path;
      _refFileName  = r.files.single.name;
      _refLoading   = true;
      _refHeaders   = [];
      _refDetectedCol = '';
      _refColBadge  = '…';
    });
    await _detectRefHeaders();
  }

  Future<void> _detectRefHeaders() async {
    if (_refFilePath == null) return;
    try {
      final api  = context.read<ApiService>();
      final data = await api.checkHeaders(smallFile: File(_refFilePath!));
      final info = data['small'] as Map<String, dynamic>?;
      if (info == null) return;
      final headers = (info['headers'] as List?)?.map((h) => h.toString()).where((h) => h.isNotEmpty).toList() ?? [];
      final detected = info['detected']?.toString() ?? '';
      setState(() {
        _refHeaders    = headers;
        _refDetectedCol = detected.isNotEmpty ? detected : (headers.isNotEmpty ? headers.first : '');
        _refColBadge   = detected.isNotEmpty ? '✔ تلقائي' : '؟ يدوي';
        _refLoading    = false;
      });
    } catch (_) {
      setState(() { _refLoading = false; _refColBadge = '⚠ خطأ'; });
    }
  }

  Future<void> _checkSinglePlate() async {
    final plate = _singlePlateCtrl.text.trim();
    if (plate.isEmpty) return;
    if (_refFilePath == null) {
      setState(() { _singlePlateResult = 'ارفع ملف المرجع أولاً'; _singlePlateOk = false; });
      return;
    }
    setState(() { _singlePlateChecking = true; _singlePlateResult = 'جاري الفحص…'; });
    try {
      final api = context.read<ApiService>();
      final ok  = await api.checkRefPlate(_refFilePath!, plate, col: _refDetectedCol);
      setState(() { _singlePlateOk = ok; _singlePlateResult = ok ? '✅ اللوحة موجودة في الشيت' : '❌ اللوحة غير موجودة في الشيت'; });
    } catch (e) {
      setState(() { _singlePlateOk = false; _singlePlateResult = 'خطأ: ${e.toString().replaceFirst("Exception: ", "")}'; });
    } finally {
      setState(() => _singlePlateChecking = false);
    }
  }

  // ── Recording ──────────────────────────────────────────────────────────────
  Future<bool> _checkMicPermission() async {
    var s = await Permission.microphone.status;
    if (!s.isGranted) s = await Permission.microphone.request();
    return s.isGranted;
  }

  Future<void> _startRecording() async {
    if (!await _checkMicPermission()) {
      _setStatus(StatusType.error, 'لا يمكن الوصول للميكروفون');
      return;
    }
    final dir  = await getTemporaryDirectory();
    final path = '${dir.path}/fc_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1, sampleRate: 16000),
      path: path,
    );

    setState(() {
      _isRecording = true; _hasStopped = false;
      _recSecs = 0; _gpsPoints = []; _gpsActive = true;
      _gpsStatus = _autoGpsMode ? 'تلقائي كل $_gpsInterval ث' : 'يدوي';
    });

    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _recSecs++);
      if (_recSecs >= _maxSecs) _stopRecording();
    });

    if (_autoGpsMode) {
      _collectGps();
      _autoGpsTimer = Timer.periodic(Duration(seconds: _gpsInterval), (_) => _collectGps());
    }
  }

  Future<void> _stopRecording() async {
    _recTimer?.cancel();
    _autoGpsTimer?.cancel();
    final path = await _recorder.stop();
    setState(() { _isRecording = false; _hasStopped = true; _recordedPath = path; _gpsActive = false; _gpsStatus = 'توقف — ${_gpsPoints.length} نقطة'; });
  }

  Future<void> _collectGps() async {
    var s = await Permission.location.status;
    if (s.isDenied) s = await Permission.location.request();
    if (!s.isGranted) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)),
      );
      if (mounted) setState(() => _gpsPoints.add(GpsPoint(lat: pos.latitude, lng: pos.longitude, accuracy: pos.accuracy.toInt())));
    } catch (_) {}
  }

  Future<void> _captureManualPin() async {
    if (!_isRecording) return;
    await _collectGps();
  }

  // ── Do Check ───────────────────────────────────────────────────────────────
  Future<void> _doCheck() async {
    if (_recordedPath == null) { _setStatus(StatusType.error, 'لا يوجد تسجيل — سجّل صوتاً أولاً'); return; }
    final cfg = context.read<AppConfig>();
    if (!cfg.hasApiKey) { _setStatus(StatusType.error, 'أدخل مفتاح API من الإعدادات'); return; }

    setState(() { _processing = true; _hasStopped = false; });
    _setStatus(StatusType.processing, 'جاري تفريغ الصوت…');

    List<PlateRow> newRows = [];
    try {
      final api = context.read<ApiService>();
      newRows = await api.processAudio(
        filePath:     _recordedPath!,
        gpsPoints:    _gpsPoints,
        recorderName: _recorderNameCtrl.text.trim(),
        sheetName:    _sheetNameCtrl.text.trim(),
      );
    } catch (e) {
      _setStatus(StatusType.error, e.toString().replaceFirst('Exception: ', ''));
      setState(() { _processing = false; });
      return;
    }

    _originGps = _midGps(_gpsPoints);
    _allRows   = [..._allRows, ...newRows];
    _saveData();
    _setStatus(StatusType.processing, 'تم التفريغ — استُخرج ${newRows.length} لوحة. جاري التشيك…');

    if (_refFilePath != null) {
      try {
        final api = context.read<ApiService>();
        final ref = await api.parseRefPlates(_refFilePath!, col: _refDetectedCol);
        final refSet = ref.map(_norm).toSet();
        _matchedRows = newRows.where((r) => refSet.contains(_norm(r.fullPlate))).toList();
        _saveData();
        final unmatched = newRows.length - _matchedRows.length;
        _setStatus(
          _matchedRows.isEmpty ? StatusType.warn : StatusType.ok,
          _matchedRows.isEmpty
              ? 'تم التفريغ — لا توجد تطابقات'
              : '✅ ${_matchedRows.length} لوحة مطابقة من أصل ${newRows.length} — إجمالي: ${_allRows.length}',
        );
      } catch (e) {
        _setStatus(StatusType.warn, 'تم التفريغ لكن فشل قراءة ملف المرجع');
      }
    } else {
      _setStatus(StatusType.ok, '✔ تم التفريغ — ${newRows.length} لوحة (لا يوجد ملف مرجعي)');
    }

    setState(() {
      _processing   = false;
      _recordedPath = null;
      _recSecs      = 0;
      _gpsPoints    = [];
    });
  }

  Future<void> _checkAll() async {
    if (_allRows.isEmpty) { _setStatus(StatusType.warn, 'لا توجد لوحات مسجّلة بعد'); return; }
    if (_refFilePath == null) { _setStatus(StatusType.error, 'ارفع ملف المرجع أولاً'); return; }

    _setStatus(StatusType.processing, 'جاري تشيك كل اللوحات…');
    try {
      final api = context.read<ApiService>();
      final ref = await api.parseRefPlates(_refFilePath!, col: _refDetectedCol);
      final refSet = ref.map(_norm).toSet();
      _matchedRows = _allRows.where((r) => refSet.contains(_norm(r.fullPlate))).toList();
      _saveData();
      setState(() {});
      _setStatus(StatusType.ok, '✅ ${_matchedRows.length} مطابقة من أصل ${_allRows.length}');
    } catch (e) {
      _setStatus(StatusType.error, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  // ── Export ─────────────────────────────────────────────────────────────────
  Future<void> _exportAll() async {
    if (_allRows.isEmpty) { _setStatus(StatusType.warn, 'لا توجد لوحات'); return; }
    _setStatus(StatusType.processing, 'جاري إنشاء ملف Excel…');
    try {
      final api   = context.read<ApiService>();
      final bytes = await api.exportExcel(_allRows, _sheetNameCtrl.text.trim());
      await _saveBytesAsExcel(bytes, 'كل_اللوحات_${DateTime.now().toIso8601String().substring(0, 10)}');
      _setStatus(StatusType.ok, '✔ تم تحميل ملف كل اللوحات');
    } catch (e) { _setStatus(StatusType.error, e.toString().replaceFirst('Exception: ', '')); }
  }

  Future<void> _exportMatched() async {
    if (_matchedRows.isEmpty) { _setStatus(StatusType.warn, 'لا توجد لوحات مطابقة'); return; }
    _setStatus(StatusType.processing, 'جاري إنشاء ملف Excel…');
    try {
      final api   = context.read<ApiService>();
      final bytes = await api.exportExcel(_matchedRows, _sheetNameCtrl.text.trim(), fieldCheck: true);
      await _saveBytesAsExcel(bytes, 'اللوحات_المطابقة_${DateTime.now().toIso8601String().substring(0, 10)}');
      _setStatus(StatusType.ok, '✔ تم تحميل ملف اللوحات المطابقة');
    } catch (e) { _setStatus(StatusType.error, e.toString().replaceFirst('Exception: ', '')); }
  }

  Future<void> _saveBytesAsExcel(List<int> bytes, String name) async {
    final dir  = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final path = '${dir.path}/$name.xlsx';
    await File(path).writeAsBytes(bytes);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم الحفظ:\n$path')));
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _norm(String s) {
    s = s.trim().replaceAll(RegExp(r'[\s\u200b]+'), '');
    s = s.replaceAll(RegExp(r'[\u0623\u0625\u0622\u0671]'), '\u0627');
    s = s.replaceAll('\u0649', '\u064a');
    s = s.replaceAll('\u0629', '\u0647');
    return s.toLowerCase();
  }

  String? _midGps(List<GpsPoint> pts) {
    if (pts.isEmpty) return null;
    final mid = pts[(pts.length - 1) ~/ 2];
    return '${mid.lat},${mid.lng}';
  }

  String _mapsUrl(String originGps, String destGps) {
    return 'https://www.google.com/maps/dir/$originGps/$destGps';
  }

  void _setStatus(StatusType t, String msg) => setState(() { _sType = t; _sMsg = msg; });

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fcAllRows_v5',  jsonEncode(_allRows.map((r) => r.toJson()).toList()));
    await prefs.setString('fcMatchedRows_v5', jsonEncode(_matchedRows.map((r) => r.toJson()).toList()));
    await prefs.setString('fcOriginGps_v5', _originGps ?? '');
  }

  Future<void> _loadPersistedData() async {
    final prefs = await SharedPreferences.getInstance();
    final al = prefs.getString('fcAllRows_v5');
    final mx = prefs.getString('fcMatchedRows_v5');
    final og = prefs.getString('fcOriginGps_v5');
    if (al != null) _allRows    = (jsonDecode(al) as List).map((j) => PlateRow.fromJson(j)).toList();
    if (mx != null) _matchedRows= (jsonDecode(mx) as List).map((j) => PlateRow.fromJson(j)).toList();
    _originGps = (og != null && og.isNotEmpty) ? og : null;
    setState(() {});
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(title: const Text('🔍 التشيك الميداني')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSettings(),
            _buildRefPanel(),
            _buildRecordPanel(),
            StatusBanner(type: _sType, message: _sMsg),
            if (_allRows.isNotEmpty) _buildAllRows(),
            if (_matchedRows.isNotEmpty) _buildMatchedRows(),
          ],
        ),
      ),
    );
  }

  Widget _buildSettings() => AppPanel(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const PanelTitle('⚙ الإعدادات', color: kTeal),
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const FieldLabel('اسم المسجّل'),
          TextField(controller: _recorderNameCtrl, style: const TextStyle(color: kText),
              decoration: const InputDecoration(hintText: 'أدخل اسمك')),
        ])),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const FieldLabel('اسم ورقة Excel'),
          TextField(controller: _sheetNameCtrl, style: const TextStyle(color: kText)),
        ])),
      ]),
    ],
  ), accentColor: kTeal);

  Widget _buildRefPanel() => AppPanel(accentColor: kTeal, child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const PanelTitle('📂 الخطوة 1 — رفع ملف المرجع', color: kTeal),
      if (_refFilePath == null)
        UploadZone(hint: 'اضغط لاختيار ملف Excel المرجعي', onTap: _pickRefFile, color: kTeal)
      else
        Row(children: [
          Expanded(child: Text('📎 $_refFileName', style: const TextStyle(color: kTeal, fontFamily: 'monospace', fontSize: 13), overflow: TextOverflow.ellipsis)),
          TextButton(onPressed: () => setState(() { _refFilePath = null; _refFileName = ''; _refHeaders = []; }), child: const Text('✕ إزالة', style: TextStyle(color: kRed, fontSize: 12))),
        ]),
      if (_refFilePath != null) ...[
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FieldLabel('عمود رقم اللوحة'),
              _refHeaders.isEmpty
                  ? Container(height: 38, decoration: BoxDecoration(color: kSurf2, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder)), child: Center(child: _refLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kTeal)) : const Text('لا توجد أعمدة', style: TextStyle(color: kDim, fontSize: 13))))
                  : DropdownButtonFormField<String>(
                      value: _refHeaders.contains(_refDetectedCol) ? _refDetectedCol : _refHeaders.first,
                      dropdownColor: kSurf2,
                      style: const TextStyle(color: kText, fontSize: 13),
                      decoration: InputDecoration(filled: true, fillColor: kSurf2, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: kBorder))),
                      items: _refHeaders.map((h) => DropdownMenuItem(value: h, child: Text(h))).toList(),
                      onChanged: (v) => setState(() => _refDetectedCol = v ?? ''),
                    ),
            ],
          )),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: StatusBadge(_refColBadge, color: _refColBadge.contains('✔') ? kGreen : kDim),
          ),
        ]),
        const SectionDivider(),
        const FieldLabel('فحص لوحة واحدة'),
        Row(children: [
          Expanded(child: TextField(
            controller: _singlePlateCtrl,
            style: const TextStyle(color: kText, fontFamily: 'monospace'),
            decoration: const InputDecoration(hintText: 'أدخل رقم اللوحة'),
            onSubmitted: (_) => _checkSinglePlate(),
          )),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _singlePlateChecking ? null : _checkSinglePlate,
            style: ElevatedButton.styleFrom(backgroundColor: kTeal, foregroundColor: Colors.white),
            child: _singlePlateChecking ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('فحص'),
          ),
        ]),
        if (_singlePlateResult.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: (_singlePlateOk ? kGreen : kRed).withOpacity(.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: (_singlePlateOk ? kGreen : kRed).withOpacity(.3)),
            ),
            child: Text(_singlePlateResult, style: TextStyle(color: _singlePlateOk ? kGreen : kRed, fontWeight: FontWeight.bold)),
          ),
      ],
    ],
  ));

  Widget _buildRecordPanel() => AppPanel(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      PanelTitle('🎙 الخطوة 2 — التسجيل', color: kTeal,
          trailing: Text(formatDuration(_recSecs) + ' / 05:00', style: const TextStyle(color: kTeal, fontFamily: 'monospace', fontSize: 12))),

      Row(children: [
        _GpsChip2(label: '⏱ تلقائي', selected: _autoGpsMode, color: kTeal, onTap: () => setState(() => _autoGpsMode = true)),
        const SizedBox(width: 8),
        _GpsChip2(label: '👆 يدوي', selected: !_autoGpsMode, color: kTeal, onTap: () => setState(() => _autoGpsMode = false)),
      ]),

      if (_isRecording)
        Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: LinearProgressIndicator(
          value: _recSecs / _maxSecs, backgroundColor: kBorder,
          color: _recSecs > 240 ? kAmber : kTeal,
        )),

      const SizedBox(height: 14),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Column(children: [
          GestureDetector(
            onTap: _isRecording ? _stopRecording : _startRecording,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 80, height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: _isRecording
                      ? [const Color(0xFFFCA5A5), kRed, const Color(0xFFDC2626)]
                      : [const Color(0xFF5EEAD4), kTeal, const Color(0xFF0D9488)],
                ),
                boxShadow: [BoxShadow(color: (_isRecording ? kRed : kTeal).withOpacity(.45), blurRadius: 16)],
              ),
              child: Icon(_isRecording ? Icons.stop : Icons.fiber_manual_record, size: 34, color: Colors.white),
            ),
          ),
          const SizedBox(height: 6),
          Text(_isRecording ? 'جاري … اضغط للإيقاف' : (_hasStopped ? 'تم الإيقاف' : 'اضغط للتسجيل'),
              style: const TextStyle(color: kDim, fontSize: 12)),
        ]),
        if (_isRecording) ...[
          const SizedBox(width: 28),
          Column(children: [
            GestureDetector(
              onTap: _captureManualPin,
              child: Container(
                width: 54, height: 54,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    gradient: const LinearGradient(colors: [Color(0xFF5EEAD4), kTeal]),
                    boxShadow: [BoxShadow(color: kTeal.withOpacity(.35), blurRadius: 12)]),
                child: const Center(child: Text('📍', style: TextStyle(fontSize: 24))),
              ),
            ),
            const SizedBox(height: 4),
            Text('${_gpsPoints.length} نقطة', style: const TextStyle(color: kTeal, fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
          ]),
        ],
      ]),

      const SizedBox(height: 12),
      Row(children: [
        Icon(Icons.circle, size: 8, color: _gpsActive ? kGreen : kDim),
        const SizedBox(width: 6),
        Text(_gpsStatus, style: const TextStyle(color: kDim, fontSize: 12, fontFamily: 'monospace')),
      ]),

      if (_hasStopped) ...[
        const SizedBox(height: 16),
        GradientButton(
          label: '🔍 التشيك',
          onPressed: _processing ? null : _doCheck,
          loading: _processing,
          colors: const [kTeal, Color(0xFF0D9488)],
          icon: Icons.search,
        ),
      ],
    ],
  ), accentColor: kTeal);

  Widget _buildAllRows() => AppPanel(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      PanelTitle('📋 جميع اللوحات المسجّلة', color: kTeal, trailing: StatusBadge('${_allRows.length} لوحة', color: kDim)),
      Wrap(spacing: 8, runSpacing: 8, children: [
        AppOutlinedButton(label: '⬇ تحميل Excel', onPressed: _exportAll, color: kTeal),
        AppOutlinedButton(label: '🔍 تشيك الكل',  onPressed: _checkAll,  color: kTeal),
        AppOutlinedButton(label: '🗑 مسح الكل',   onPressed: () { setState(() { _allRows.clear(); _matchedRows.clear(); }); _saveData(); }, color: kRed),
      ]),
      const SizedBox(height: 10),
      ..._allRows.take(30).map((r) => _PlateRowTile(row: r)),
      if (_allRows.length > 30)
        Padding(padding: const EdgeInsets.only(top: 6), child: Text('+ ${_allRows.length - 30} لوحة أخرى …', style: const TextStyle(color: kDim, fontSize: 12))),
    ],
  ), accentColor: kTeal);

  Widget _buildMatchedRows() => AppPanel(accentColor: kGreen, child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      PanelTitle('✅ نتائج التشيك — اللوحات المطابقة', color: kGreen),
      Row(children: [
        _StatCard('${_matchedRows.length}', 'لوحة مطابقة', kGreen),
        const SizedBox(width: 8),
        _StatCard('${(_allRows.length > 0 ? _allRows.length : 0) - _matchedRows.length}', 'غير موجودة', kRed),
        const SizedBox(width: 8),
        _StatCard('${_allRows.length}', 'مسجّل', kTeal),
      ]),
      const SizedBox(height: 10),
      ..._matchedRows.map((r) => _PlateRowTile(
        row: r,
        matched: true,
        mapsUrl: (_originGps != null && r.gps.isNotEmpty)
            ? _mapsUrl(_originGps!, r.gps) : null,
      )),
      const SizedBox(height: 10),
      GradientButton(label: '⬇ تحميل Excel (المطابقة)', onPressed: _exportMatched,
          colors: const [kGreen, Color(0xFF16A34A)]),
    ],
  ));
}

// ── Subwidgets ─────────────────────────────────────────────────────────────
class _GpsChip2 extends StatelessWidget {
  final String label; final bool selected; final Color color; final VoidCallback onTap;
  const _GpsChip2({required this.label, required this.selected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? color.withOpacity(.15) : kSurf2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: selected ? color.withOpacity(.5) : kBorder),
      ),
      child: Text(label, style: TextStyle(color: selected ? color : kDim, fontWeight: selected ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
    ),
  );
}

class _PlateRowTile extends StatelessWidget {
  final PlateRow row; final bool matched; final String? mapsUrl;
  const _PlateRowTile({required this.row, this.matched = false, this.mapsUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: matched ? kGreen.withOpacity(.06) : kSurf2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: matched ? kGreen.withOpacity(.25) : kBorder),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(row.fullPlate, style: TextStyle(color: matched ? kGreen : kSky, fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'monospace')),
          if (row.vehicleType.isNotEmpty || row.streetName.isNotEmpty)
            Text('${row.vehicleType} · ${row.streetName}', style: const TextStyle(color: kDim, fontSize: 11)),
          if (row.gps.isNotEmpty)
            Text(row.gps, style: const TextStyle(color: kDim, fontSize: 10, fontFamily: 'monospace')),
        ])),
        if (mapsUrl != null)
          IconButton(
            icon: const Icon(Icons.map_outlined, size: 20, color: kTeal),
            tooltip: 'فتح الخريطة',
            onPressed: () => launchUrl(Uri.parse(mapsUrl!), mode: LaunchMode.externalApplication),
          ),
      ]),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value, label; final Color color;
  const _StatCard(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(color: kSurf2, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder)),
      child: Column(children: [
        Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        Text(label, style: const TextStyle(color: kDim, fontSize: 11)),
      ]),
    ));
  }
}
