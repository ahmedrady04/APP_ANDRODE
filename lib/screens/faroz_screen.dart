import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';

class FarozScreen extends StatefulWidget {
  const FarozScreen({super.key});

  @override
  State<FarozScreen> createState() => _FarozScreenState();
}

class _FarozScreenState extends State<FarozScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // ── Files ──────────────────────────────────────────────────────────────────
  File?   _largeFile;
  String  _largeName      = '';
  List<String> _largeHeaders = [];
  String  _largeDetected  = '';
  bool    _largeLoading   = false;

  File?   _smallFile;
  String  _smallName      = '';
  List<String> _smallHeaders = [];
  String  _smallDetected  = '';
  bool    _smallLoading   = false;

  final _largePwCtrl = TextEditingController();
  bool _showLargePw  = false;

  // ── Result ─────────────────────────────────────────────────────────────────
  List<int>? _resultBytes;
  int _matchedCount   = 0;
  int _unmatchedCount = 0;

  // ── Status ─────────────────────────────────────────────────────────────────
  StatusType _sType = StatusType.info;
  String     _sMsg  = '';
  bool       _running = false;

  @override
  void dispose() {
    _largePwCtrl.dispose();
    super.dispose();
  }

  // ── Pick files ─────────────────────────────────────────────────────────────
  Future<void> _pickLarge() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls']);
    if (r == null || r.files.single.path == null) return;
    setState(() {
      _largeFile    = File(r.files.single.path!);
      _largeName    = r.files.single.name;
      _largeHeaders = [];
      _largeDetected= '';
      _resultBytes  = null;
    });
    await _detectHeaders('large');
  }

  Future<void> _pickSmall() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls']);
    if (r == null || r.files.single.path == null) return;
    setState(() {
      _smallFile    = File(r.files.single.path!);
      _smallName    = r.files.single.name;
      _smallHeaders = [];
      _smallDetected= '';
      _resultBytes  = null;
    });
    await _detectHeaders('small');
  }

  Future<void> _detectHeaders(String side) async {
    final api = context.read<ApiService>();
    setState(() => side == 'large' ? _largeLoading = true : _smallLoading = true);
    try {
      final data = await api.checkHeaders(
        largeFile: side == 'large' ? _largeFile : null,
        smallFile: side == 'small' ? _smallFile : null,
        password:  side == 'large' ? _largePwCtrl.text.trim() : '',
      );
      final info = data[side] as Map<String, dynamic>?;
      if (info == null) return;
      final headers  = (info['headers'] as List?)?.map((h) => h.toString()).where((h) => h.isNotEmpty).toList() ?? [];
      final detected = info['detected']?.toString() ?? '';
      setState(() {
        if (side == 'large') {
          _largeHeaders  = headers;
          _largeDetected = detected.isNotEmpty ? detected : (headers.isNotEmpty ? headers.first : '');
        } else {
          _smallHeaders  = headers;
          _smallDetected = detected.isNotEmpty ? detected : (headers.isNotEmpty ? headers.first : '');
        }
      });
    } catch (_) {}
    setState(() => side == 'large' ? _largeLoading = false : _smallLoading = false);
  }

  // ── Run check ─────────────────────────────────────────────────────────────
  Future<void> _runCheck() async {
    if (_largeFile == null || _smallFile == null) {
      _setStatus(StatusType.error, 'يرجى رفع كلا الملفين أولاً');
      return;
    }
    setState(() { _running = true; _resultBytes = null; });
    _setStatus(StatusType.processing, 'جاري المطابقة…');

    try {
      final api   = context.read<ApiService>();
      final bytes = await api.checkFiles(
        largeFile: _largeFile!,
        smallFile: _smallFile!,
        password:  _largePwCtrl.text.trim(),
        largeCol:  _largeDetected,
        smallCol:  _smallDetected,
      );
      if (bytes != null) {
        setState(() { _resultBytes = bytes; });
        _setStatus(StatusType.ok, '✅ تمت المطابقة — اضغط لتحميل ملف النتائج');
      }
    } catch (e) {
      _setStatus(StatusType.warn, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => _running = false);
    }
  }

  Future<void> _downloadResult() async {
    if (_resultBytes == null) return;
    final dir  = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final ts   = DateTime.now().toIso8601String().substring(0, 16).replaceAll(':', '-').replaceAll('T', '_');
    final path = '${dir.path}/التطابقات_$ts.xlsx';
    await File(path).writeAsBytes(_resultBytes!);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم الحفظ:\n$path')));
  }

  void _setStatus(StatusType t, String msg) => setState(() { _sType = t; _sMsg = msg; });

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(title: const Text('✅ الفرز — مطابقة اللوحات')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppPanel(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                'ارفع الملف الكبير (مصدر البيانات) والملف الصغير (قائمة البحث).\n'
                'سيتم اكتشاف عمود اللوحة تلقائياً والمطابقة فور الضغط.',
                style: TextStyle(color: kDim, fontSize: 13, height: 1.6),
              ),
            ),

            // Large file card
            _FileCard(
              title: '📂 الملف الكبير',
              subtitle: 'مصدر البيانات',
              titleColor: kSky,
              fileName:  _largeName,
              headers:   _largeHeaders,
              detected:  _largeDetected,
              loading:   _largeLoading,
              onDetectedChanged: (v) => setState(() => _largeDetected = v),
              onPick:    _pickLarge,
              onRemove:  () => setState(() { _largeFile = null; _largeName = ''; _largeHeaders = []; }),
              extraContent: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  const FieldLabel('🔒 كلمة المرور (إن وجدت)'),
                  Row(children: [
                    Expanded(child: TextField(
                      controller: _largePwCtrl,
                      obscureText: !_showLargePw,
                      style: const TextStyle(color: kText, fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        hintText: 'اتركه فارغاً إن لم يكن محمياً',
                        suffixIcon: IconButton(
                          icon: Icon(_showLargePw ? Icons.visibility_off : Icons.visibility, color: kDim, size: 18),
                          onPressed: () { setState(() => _showLargePw = !_showLargePw); _detectHeaders('large'); },
                        ),
                      ),
                    )),
                  ]),
                ],
              ),
            ),

            const SizedBox(height: 4),

            // Small file card
            _FileCard(
              title: '📋 الملف الصغير',
              subtitle: 'قائمة البحث',
              titleColor: kViolet,
              fileName:  _smallName,
              headers:   _smallHeaders,
              detected:  _smallDetected,
              loading:   _smallLoading,
              onDetectedChanged: (v) => setState(() => _smallDetected = v),
              onPick:    _pickSmall,
              onRemove:  () => setState(() { _smallFile = null; _smallName = ''; _smallHeaders = []; }),
            ),

            const SizedBox(height: 8),

            StatusBanner(type: _sType, message: _sMsg),

            // Action button
            GradientButton(
              label: '🔍 مطابقة وتحميل النتائج',
              onPressed: (_largeFile != null && _smallFile != null && !_running) ? _runCheck : null,
              colors: const [kViolet, Color(0xFF6D28D9)],
              loading: _running,
              icon: Icons.search,
            ),

            // Result download
            if (_resultBytes != null) ...[
              const SizedBox(height: 12),
              AppPanel(accentColor: kGreen, child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PanelTitle('📊 نتيجة المطابقة', color: kGreen),
                  Row(children: [
                    _StatChip('✔', 'صفوف مطابقة', kGreen),
                    const SizedBox(width: 8),
                    _StatChip('${_largeDetected.isNotEmpty ? _largeDetected : "—"}', 'عمود الكبير', kSky),
                    const SizedBox(width: 8),
                    _StatChip('${_smallDetected.isNotEmpty ? _smallDetected : "—"}', 'عمود الصغير', kViolet),
                  ]),
                  const SizedBox(height: 12),
                  GradientButton(
                    label: '⬇ تحميل ملف التطابقات (Excel)',
                    onPressed: _downloadResult,
                    colors: const [kGreen, Color(0xFF16A34A)],
                    icon: Icons.download,
                  ),
                ],
              )),
            ],
          ],
        ),
      ),
    );
  }
}

// ── File Card ──────────────────────────────────────────────────────────────
class _FileCard extends StatelessWidget {
  final String  title, subtitle;
  final Color   titleColor;
  final String  fileName;
  final List<String> headers;
  final String  detected;
  final bool    loading;
  final ValueChanged<String> onDetectedChanged;
  final VoidCallback onPick, onRemove;
  final Widget? extraContent;

  const _FileCard({
    required this.title,
    required this.subtitle,
    required this.titleColor,
    required this.fileName,
    required this.headers,
    required this.detected,
    required this.loading,
    required this.onDetectedChanged,
    required this.onPick,
    required this.onRemove,
    this.extraContent,
  });

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      accentColor: titleColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(title, style: TextStyle(color: titleColor, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(width: 8),
                StatusBadge(subtitle, color: titleColor),
              ]),
            ])),
          ]),
          const SizedBox(height: 10),
          if (fileName.isEmpty)
            UploadZone(hint: 'اضغط أو اسحب ملف Excel', color: titleColor, onTap: onPick)
          else
            Row(children: [
              Expanded(child: Text('📎 $fileName', style: TextStyle(color: titleColor, fontFamily: 'monospace', fontSize: 12), overflow: TextOverflow.ellipsis)),
              TextButton(onPressed: onRemove, child: const Text('✕', style: TextStyle(color: kRed))),
            ]),

          if (extraContent != null) extraContent!,

          if (fileName.isNotEmpty) ...[
            const SizedBox(height: 10),
            const FieldLabel('عمود اللوحة'),
            Row(children: [
              Expanded(child: loading
                  ? Container(height: 42, alignment: Alignment.center, decoration: BoxDecoration(color: kSurf2, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder)), child: const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kSky)))
                  : headers.isEmpty
                      ? Container(height: 42, alignment: Alignment.center, decoration: BoxDecoration(color: kSurf2, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder)), child: const Text('ادخل كلمة المرور ثم اضغط 🔒', style: TextStyle(color: kDim, fontSize: 12)))
                      : DropdownButtonFormField<String>(
                          value: headers.contains(detected) ? detected : null,
                          dropdownColor: kSurf2,
                          style: const TextStyle(color: kText, fontSize: 13),
                          hint: const Text('اختر عموداً…', style: TextStyle(color: kDim)),
                          decoration: InputDecoration(filled: true, fillColor: kSurf2, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: kBorder))),
                          items: headers.map((h) => DropdownMenuItem(value: h, child: Text(h))).toList(),
                          onChanged: (v) { if (v != null) onDetectedChanged(v); },
                        )),
              const SizedBox(width: 8),
              StatusBadge(detected.isNotEmpty ? '✔ مختار' : '—', color: detected.isNotEmpty ? kGreen : kDim),
            ]),
          ],
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String value, label; final Color color;
  const _StatChip(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(color: kSurf2, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder)),
    child: Column(children: [
      Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace')),
      Text(label, style: const TextStyle(color: kDim, fontSize: 10)),
    ]),
  ));
}
