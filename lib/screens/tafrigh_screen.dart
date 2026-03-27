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
import '../config.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';

class TafrighScreen extends StatefulWidget {
  const TafrighScreen({super.key});

  @override
  State<TafrighScreen> createState() => _TafrighScreenState();
}

class _TafrighScreenState extends State<TafrighScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // ── State ──────────────────────────────────────────────────────────────────
  final _recorderNameCtrl = TextEditingController();
  final _sheetNameCtrl    = TextEditingController(text: 'بيانات المركبات');

  final _recorder = AudioRecorder();
  bool  _isRecording  = false;
  bool  _hasStopped   = false;
  String? _recordedPath;
  int   _recSecs      = 0;
  Timer? _recTimer;

  List<GpsPoint> _gpsPoints  = [];
  Timer? _autoGpsTimer;
  bool   _autoGpsMode = true;
  int    _gpsInterval = 5;
  String _gpsStatus   = 'في انتظار التسجيل';
  bool   _gpsActive   = false;

  List<QueueItem> _queue = [];
  List<PlateRow>  _rows  = [];

  StatusType _statusType = StatusType.info;
  String     _statusMsg  = '';
  bool       _processing  = false;

  static const int _maxSecs = 300;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadTable();
  }

  @override
  void dispose() {
    _recTimer?.cancel();
    _autoGpsTimer?.cancel();
    _recorder.dispose();
    _recorderNameCtrl.dispose();
    _sheetNameCtrl.dispose();
    super.dispose();
  }

  // ── Permissions ────────────────────────────────────────────────────────────
  Future<bool> _checkMicPermission() async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> _checkLocationPermission() async {
    var status = await Permission.location.status;
    if (status.isDenied) status = await Permission.location.request();
    if (status.isPermanentlyDenied) { openAppSettings(); return false; }
    return status.isGranted;
  }

  // ── Recording ──────────────────────────────────────────────────────────────
  Future<void> _startRecording() async {
    if (!await _checkMicPermission()) {
      _setStatus(StatusType.error, 'لا يمكن الوصول للميكروفون — تحقق من الصلاحيات');
      return;
    }

    final dir  = await getTemporaryDirectory();
    final path = '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1, sampleRate: 16000),
      path: path,
    );

    setState(() {
      _isRecording = true;
      _hasStopped  = false;
      _recSecs     = 0;
      _gpsPoints   = [];
      _gpsActive   = true;
      _gpsStatus   = _autoGpsMode ? 'تلقائي كل $_gpsInterval ث' : 'يدوي — اضغط 📍 لكل سيارة';
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
    setState(() {
      _isRecording   = false;
      _hasStopped    = true;
      _recordedPath  = path;
      _gpsActive     = false;
      _gpsStatus     = 'توقف — ${_gpsPoints.length} نقطة';
    });
  }

  Future<void> _collectGps() async {
    if (!await _checkLocationPermission()) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)),
      );
      final pt = GpsPoint(lat: pos.latitude, lng: pos.longitude, accuracy: pos.accuracy.toInt());
      if (mounted) setState(() => _gpsPoints.add(pt));
    } catch (_) {}
  }

  Future<void> _captureManualPin() async {
    if (!_isRecording) return;
    await _collectGps();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('📍 تم تسجيل نقطة GPS'), duration: Duration(seconds: 1)),
      );
    }
  }

  // ── Queue & Send ───────────────────────────────────────────────────────────
  void _addToQueue() {
    if (_recordedPath == null) return;
    final item = QueueItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'تسجيل — ${TimeOfDay.now().format(context)} (${formatDuration(_recSecs)})',
      filePath: _recordedPath!,
      gps: List.from(_gpsPoints),
      durationSecs: _recSecs,
    );
    setState(() {
      _queue.add(item);
      _hasStopped   = false;
      _recordedPath = null;
    });
    _setStatus(StatusType.ok, '✔ أُضيف إلى القائمة');
  }

  Future<void> _sendItem(QueueItem item) async {
    final cfg = context.read<AppConfig>();
    if (!cfg.hasApiKey) { _setStatus(StatusType.error, 'أدخل مفتاح API من الإعدادات'); return; }

    setState(() { item.status = QueueStatus.processing; _processing = true; });
    _setStatus(StatusType.processing, 'جاري تحليل "${item.name}" …');

    try {
      final api    = context.read<ApiService>();
      final plates = await api.processAudio(
        filePath:     item.filePath,
        gpsPoints:    item.gps,
        recorderName: _recorderNameCtrl.text.trim(),
        sheetName:    _sheetNameCtrl.text.trim(),
      );
      setState(() {
        item.status = QueueStatus.done;
        _rows.addAll(plates);
        _processing = false;
      });
      _saveTable();
      _setStatus(StatusType.ok, '✔ استُخرج ${plates.length} لوحة من "${item.name}"');
    } catch (e) {
      setState(() { item.status = QueueStatus.error; item.lastError = _friendlyErr(e.toString()); _processing = false; });
      _setStatus(StatusType.warn, '⚠ فشل: ${item.lastError}');
    }
  }

  Future<void> _sendAll() async {
    final pending = _queue.where((i) => i.status == QueueStatus.pending || i.status == QueueStatus.error).toList();
    for (final item in pending) {
      await _sendItem(item);
      await Future.delayed(const Duration(milliseconds: 600));
    }
  }

  Future<void> _directSend() async {
    if (_recordedPath == null) return;
    final item = QueueItem(
      id: 'direct',
      name: 'إرسال مباشر',
      filePath: _recordedPath!,
      gps: List.from(_gpsPoints),
      durationSecs: _recSecs,
    );
    setState(() { _queue.add(item); _hasStopped = false; _recordedPath = null; });
    await _sendItem(item);
  }

  // ── Import / Export Excel ──────────────────────────────────────────────────
  Future<void> _importExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['xlsx', 'xls'],
    );
    if (result == null || result.files.single.path == null) return;

    _setStatus(StatusType.processing, 'جاري قراءة الملف …');
    try {
      final api  = context.read<ApiService>();
      final rows = await api.importExcel(result.files.single.path!);
      setState(() => _rows.addAll(rows));
      _saveTable();
      _setStatus(StatusType.ok, '✔ تم استيراد ${rows.length} صف');
    } catch (e) {
      _setStatus(StatusType.error, 'خطأ في الاستيراد: ${e.toString().replaceFirst("Exception: ", "")}');
    }
  }

  Future<void> _exportExcel() async {
    if (_rows.isEmpty) { _setStatus(StatusType.warn, 'الجدول فارغ'); return; }
    _setStatus(StatusType.processing, 'جاري تصدير Excel …');
    try {
      final api   = context.read<ApiService>();
      final bytes = await api.exportExcel(_rows, _sheetNameCtrl.text.trim());
      await _saveExcelFile(bytes, 'تفريغ_${_sheetNameCtrl.text.trim()}');
      _setStatus(StatusType.ok, '✔ تم تحميل ملف Excel');
    } catch (e) {
      _setStatus(StatusType.error, 'خطأ في التصدير: ${e.toString().replaceFirst("Exception: ", "")}');
    }
  }

  Future<void> _saveExcelFile(List<int> bytes, String name) async {
    final dir  = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final path = '${dir.path}/$name.xlsx';
    await File(path).writeAsBytes(bytes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم الحفظ:\n$path'),
          action: SnackBarAction(label: 'حسناً', onPressed: () {}),
        ),
      );
    }
  }

  // ── Persistence ────────────────────────────────────────────────────────────
  Future<void> _saveTable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('plateTable_v5', jsonEncode(_rows.map((r) => r.toJson()).toList()));
  }

  Future<void> _loadTable() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('plateTable_v5');
    if (s != null) {
      final list = jsonDecode(s) as List;
      setState(() => _rows = list.map((j) => PlateRow.fromJson(j)).toList());
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  void _setStatus(StatusType t, String msg) => setState(() { _statusType = t; _statusMsg = msg; });

  String _friendlyErr(String raw) {
    if (raw.contains('429') || raw.contains('RESOURCE_EXHAUSTED')) return 'انتهت الحصة المجانية — حاول لاحقاً';
    if (raw.contains('403') || raw.contains('PERMISSION_DENIED'))  return 'مفتاح API غير مصرح له';
    if (raw.contains('microphone') || raw.contains('ميكروفون'))    return 'لا يمكن الوصول للميكروفون';
    if (raw.contains('Failed to fetch') || raw.contains('network')) return 'خطأ في الشبكة';
    final clean = raw.replaceFirst('Exception: ', '');
    return clean.length > 120 ? '${clean.substring(0, 120)}…' : clean;
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('🏙 التفريغ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showHelp,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSettings(),
            _buildRecordPanel(),
            _buildQueue(),
            StatusBanner(type: _statusType, message: _statusMsg),
            _buildTable(),
          ],
        ),
      ),
    );
  }

  // ── Settings panel ─────────────────────────────────────────────────────────
  Widget _buildSettings() {
    return AppPanel(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PanelTitle('⚙ إعدادات التفريغ'),
        Row(children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FieldLabel('اسم المسجّل'),
              TextField(controller: _recorderNameCtrl, style: const TextStyle(color: kText),
                  decoration: const InputDecoration(hintText: 'أدخل اسمك')),
            ],
          )),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FieldLabel('اسم ورقة Excel'),
              TextField(controller: _sheetNameCtrl, style: const TextStyle(color: kText)),
            ],
          )),
        ]),
      ],
    ));
  }

  // ── Recording panel ────────────────────────────────────────────────────────
  Widget _buildRecordPanel() {
    return AppPanel(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PanelTitle('🎙 التسجيل', trailing:
          Text(formatDuration(_recSecs) + ' / 05:00',
              style: const TextStyle(color: kSky, fontFamily: 'monospace', fontSize: 13))),

        // GPS mode chips
        Row(children: [
          _GpsChip(label: '⏱ تلقائي', selected: _autoGpsMode,  onTap: () => setState(() => _autoGpsMode = true)),
          const SizedBox(width: 8),
          _GpsChip(label: '👆 يدوي',  selected: !_autoGpsMode, onTap: () => setState(() => _autoGpsMode = false)),
        ]),
        if (_autoGpsMode) ...[
          const SizedBox(height: 10),
          Row(children: [
            const Text('كل: ', style: TextStyle(color: kDim, fontSize: 13)),
            SizedBox(
              width: 90,
              child: TextField(
                style: const TextStyle(color: kText, fontFamily: 'monospace'),
                decoration: const InputDecoration(suffixText: 'ث', isDense: true),
                keyboardType: TextInputType.number,
                controller: TextEditingController(text: '$_gpsInterval')
                  ..selection = TextSelection.collapsed(offset: '$_gpsInterval'.length),
                onChanged: (v) => _gpsInterval = int.tryParse(v) ?? 5,
              ),
            ),
          ]),
        ],
        const SizedBox(height: 16),

        // Progress bar
        if (_isRecording) ...[
          LinearProgressIndicator(
            value: _recSecs / _maxSecs,
            backgroundColor: kBorder,
            color: _recSecs > 240 ? kAmber : kSky,
          ),
          const SizedBox(height: 12),
        ],

        // Main record button + GPS pin
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Column(children: [
            _RecordButton(
              isRecording: _isRecording,
              onPressed:   _isRecording ? _stopRecording : _startRecording,
            ),
            const SizedBox(height: 6),
            Text(_isRecording ? 'جاري التسجيل … اضغط للإيقاف' : (_hasStopped ? 'تم الإيقاف' : 'اضغط للتسجيل'),
                style: const TextStyle(color: kDim, fontSize: 12)),
          ]),
          if (_isRecording) ...[
            const SizedBox(width: 32),
            Column(children: [
              _PinButton(onPressed: _captureManualPin),
              const SizedBox(height: 6),
              Text('${_gpsPoints.length} نقطة',
                  style: const TextStyle(color: kTeal, fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold)),
            ]),
          ],
        ]),

        const SizedBox(height: 14),

        // GPS info chips
        Wrap(spacing: 8, runSpacing: 8, children: [
          InfoChip(label: 'نقاط GPS', value: '${_gpsPoints.length}'),
          InfoChip(label: 'المدة', value: formatDuration(_recSecs)),
          if (_gpsPoints.isNotEmpty) ...[
            InfoChip(label: 'lat', value: _gpsPoints.last.lat.toStringAsFixed(5)),
            InfoChip(label: 'lng', value: _gpsPoints.last.lng.toStringAsFixed(5)),
          ],
        ]),

        if (_gpsStatus.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.circle, size: 8, color: _gpsActive ? kGreen : kDim),
            const SizedBox(width: 6),
            Text(_gpsStatus, style: const TextStyle(color: kDim, fontSize: 12, fontFamily: 'monospace')),
          ]),
        ],

        const SizedBox(height: 16),

        // Post-stop action buttons
        if (_hasStopped) ...[
          Row(children: [
            Expanded(child: GradientButton(
              label: '+ إضافة للقائمة', onPressed: _addToQueue,
              colors: const [kGreen, Color(0xFF16A34A)], height: 44,
            )),
            const SizedBox(width: 10),
            Expanded(child: GradientButton(
              label: '⚡ إرسال مباشر', onPressed: _processing ? null : _directSend,
              colors: const [kAmber, Color(0xFFD97706)], height: 44,
              loading: _processing,
            )),
          ]),
        ],
      ],
    ));
  }

  // ── Queue panel ────────────────────────────────────────────────────────────
  Widget _buildQueue() {
    final hasPending = _queue.any((i) => i.status == QueueStatus.pending || i.status == QueueStatus.error);

    return AppPanel(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PanelTitle('📋 قائمة التسجيلات',
          trailing: StatusBadge('${_queue.length}', color: kSky)),

        if (_queue.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text('لا توجد تسجيلات — سجّل وأضف للقائمة', style: TextStyle(color: kDim, fontSize: 13))),
          )
        else ...[
          ..._queue.map((item) => _QueueItemCard(
            item: item,
            onSend:   () => _sendItem(item),
            onDelete: () => setState(() => _queue.remove(item)),
            canSend:  !_processing,
          )),
          const SizedBox(height: 8),
          GradientButton(
            label: '⚡ إرسال كل الملفات المعلقة بالترتيب',
            onPressed: hasPending && !_processing ? _sendAll : null,
            loading: _processing,
          ),
        ],
      ],
    ));
  }

  // ── Table panel ────────────────────────────────────────────────────────────
  Widget _buildTable() {
    return AppPanel(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PanelTitle('📊 جدول البيانات', trailing:
          StatusBadge('${_rows.length} صف', color: kDim)),

        // Toolbar
        Wrap(spacing: 8, runSpacing: 8, children: [
          AppOutlinedButton(label: '⬇ Excel', onPressed: _exportExcel, color: kSky, icon: Icons.download),
          AppOutlinedButton(label: '⬆ استيراد', onPressed: _importExcel, color: kCyan, icon: Icons.upload),
          AppOutlinedButton(label: '+ صف', onPressed: () => setState(() { _rows.add(PlateRow()); _saveTable(); }), color: kGreen),
          AppOutlinedButton(label: '🗑 مسح الكل', onPressed: _rows.isEmpty ? null : () { setState(() => _rows.clear()); _saveTable(); }, color: kRed),
        ]),
        const SizedBox(height: 12),

        if (_rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: Text('لا توجد بيانات — أرسل تسجيلاً لاستخراج اللوحات', style: TextStyle(color: kDim))),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: MaterialStateProperty.all(kSurf2),
              columnSpacing: 16,
              columns: const [
                DataColumn(label: Text('#', style: TextStyle(color: kDim, fontSize: 11))),
                DataColumn(label: Text('رقم اللوحة', style: TextStyle(color: kSky, fontSize: 11))),
                DataColumn(label: Text('النوع', style: TextStyle(color: kSky, fontSize: 11))),
                DataColumn(label: Text('الشارع', style: TextStyle(color: kSky, fontSize: 11))),
                DataColumn(label: Text('GPS', style: TextStyle(color: kSky, fontSize: 11))),
                DataColumn(label: Text('', style: TextStyle(color: kSky, fontSize: 11))),
              ],
              rows: _rows.asMap().entries.map((e) {
                final i = e.key; final r = e.value;
                return DataRow(cells: [
                  DataCell(Text('${i+1}', style: const TextStyle(color: kDim, fontFamily: 'monospace', fontSize: 12))),
                  DataCell(Text(r.fullPlate, style: const TextStyle(color: kSky, fontWeight: FontWeight.bold, fontSize: 13))),
                  DataCell(Text(r.vehicleType, style: const TextStyle(color: kText, fontSize: 13))),
                  DataCell(Text(r.streetName, style: const TextStyle(color: kText, fontSize: 13))),
                  DataCell(Text(r.gps.isEmpty ? '—' : r.gps, style: const TextStyle(color: kDim, fontFamily: 'monospace', fontSize: 11))),
                  DataCell(IconButton(
                    icon: const Icon(Icons.close, size: 16, color: kDim),
                    onPressed: () => setState(() { _rows.removeAt(i); _saveTable(); }),
                  )),
                ]);
              }).toList(),
            ),
          ),
      ],
    ));
  }

  void _showHelp() {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: kSurf,
      title: const Text('تعليمات', style: TextStyle(color: kSky)),
      content: const Text(
        '1. أدخل اسمك واسم ورقة Excel\n'
        '2. اضغط 🔴 لبدء التسجيل\n'
        '3. GPS يُسجَّل تلقائياً أثناء التسجيل\n'
        '4. اضغط 🛑 لإيقاف التسجيل\n'
        '5. اختر "إضافة للقائمة" أو "إرسال مباشر"\n'
        '6. النتائج تظهر في الجدول أسفل الصفحة\n\n'
        '⚙ تأكد من إدخال مفتاح Gemini API في الإعدادات',
        style: TextStyle(color: kText, height: 1.7, fontSize: 14),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('حسناً', style: TextStyle(color: kSky)))],
    ));
  }
}

// ── Record Button Widget ───────────────────────────────────────────────────
class _RecordButton extends StatelessWidget {
  final bool isRecording;
  final VoidCallback onPressed;

  const _RecordButton({required this.isRecording, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 84, height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: isRecording
                ? [const Color(0xFFFCA5A5), const Color(0xFFEF4444), const Color(0xFFDC2626)]
                : [const Color(0xFF7DD3FC), kSky, const Color(0xFF0284C7)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: (isRecording ? kRed : kSky).withOpacity(.5),
              blurRadius: isRecording ? 20 : 16, spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(isRecording ? Icons.stop : Icons.fiber_manual_record,
            size: 36, color: Colors.white),
      ),
    );
  }
}

// ── GPS Pin Button ─────────────────────────────────────────────────────────
class _PinButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _PinButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 58, height: 58,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(colors: [Color(0xFF5EEAD4), kTeal]),
          boxShadow: [BoxShadow(color: kTeal.withOpacity(.4), blurRadius: 14)],
        ),
        child: const Center(child: Text('📍', style: TextStyle(fontSize: 26))),
      ),
    );
  }
}

// ── GPS Mode Chip ──────────────────────────────────────────────────────────
class _GpsChip extends StatelessWidget {
  final String label;
  final bool   selected;
  final VoidCallback onTap;

  const _GpsChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? kSky.withOpacity(.15) : kSurf2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? kSky.withOpacity(.5) : kBorder),
        ),
        child: Text(label, style: TextStyle(
          color: selected ? kSky : kDim,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          fontSize: 13,
        )),
      ),
    );
  }
}

// ── Queue Item Card ────────────────────────────────────────────────────────
class _QueueItemCard extends StatelessWidget {
  final QueueItem item;
  final VoidCallback onSend;
  final VoidCallback onDelete;
  final bool         canSend;

  const _QueueItemCard({required this.item, required this.onSend, required this.onDelete, required this.canSend});

  @override
  Widget build(BuildContext context) {
    final (statusText, statusColor) = switch (item.status) {
      QueueStatus.pending    => ('⏳ معلق',        kDim),
      QueueStatus.processing => ('🔵 جاري…',       kSky),
      QueueStatus.done       => ('✅ تم',           kGreen),
      QueueStatus.error      => ('❌ فشل',          kRed),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kSurf2,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: item.status == QueueStatus.done ? kGreen.withOpacity(.25) : kBorder),
      ),
      child: Row(children: [
        Text(item.status == QueueStatus.done ? '✅' : '🎵', style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.name, style: const TextStyle(color: kText, fontWeight: FontWeight.bold, fontSize: 13),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Row(children: [
              Text('${item.gps.length} نقطة GPS · ${formatDuration(item.durationSecs)}',
                  style: const TextStyle(color: kDim, fontSize: 11, fontFamily: 'monospace')),
              const SizedBox(width: 8),
              StatusBadge(statusText, color: statusColor),
            ]),
            if (item.lastError.isNotEmpty)
              Text(item.lastError, style: const TextStyle(color: kRed, fontSize: 11), maxLines: 2),
          ],
        )),
        const SizedBox(width: 8),
        Column(children: [
          if (item.status != QueueStatus.done)
            IconButton(
              icon: const Icon(Icons.send, size: 18, color: kSky),
              onPressed: canSend ? onSend : null,
              tooltip: 'إرسال',
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: kDim),
            onPressed: onDelete,
            tooltip: 'حذف',
          ),
        ]),
      ]),
    );
  }
}
