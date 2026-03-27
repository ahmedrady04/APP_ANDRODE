import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../services/auth_service.dart';
import '../widgets/common_widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlCtrl    = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final _orsCtrl    = TextEditingController();
  final _gmapsCtrl  = TextEditingController();
  final _manualCtrl = TextEditingController();

  bool _showApiKey  = false;
  bool _showOrs     = false;
  bool _showGmaps   = false;
  int  _modelTab    = 1;

  static const Map<int, String> _modelLabels = {
    1: 'الوضع 1 — gemini-2.5-flash (سريع)',
    2: 'الوضع 2 — gemini-3-flash-preview',
    3: 'يدوي — أدخل اسم النموذج',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFromConfig());
  }

  void _loadFromConfig() {
    final cfg = context.read<AppConfig>();
    _urlCtrl.text    = cfg.backendUrl;
    _apiKeyCtrl.text = cfg.apiKey;
    _orsCtrl.text    = cfg.orsKey;
    _gmapsCtrl.text  = cfg.googleMapsKey;
    _manualCtrl.text = cfg.modelManual;
    setState(() => _modelTab = cfg.modelTab);
  }

  Future<void> _save() async {
    final cfg = context.read<AppConfig>();
    cfg.update(
      url:    _urlCtrl.text.trim(),
      key:    _apiKeyCtrl.text.trim(),
      ors:    _orsCtrl.text.trim(),
      gmaps:  _gmapsCtrl.text.trim(),
      tab:    _modelTab,
      manual: _manualCtrl.text.trim(),
    );
    await cfg.save();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✔ تم الحفظ'), backgroundColor: kGreen),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('⚙ الإعدادات')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Backend URL
            AppPanel(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PanelTitle('🌐 رابط الخادم (Railway)'),
                TextField(
                  controller: _urlCtrl,
                  style: const TextStyle(color: kText, fontFamily: 'monospace', fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'https://your-app.railway.app',
                    prefixIcon: Icon(Icons.cloud, color: kDim, size: 18),
                  ),
                  keyboardType: TextInputType.url,
                  textDirection: TextDirection.ltr,
                ),
              ],
            )),

            // Gemini API Key
            AppPanel(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PanelTitle('🔑 مفتاح Gemini API'),
                Row(children: [
                  Expanded(child: TextField(
                    controller: _apiKeyCtrl,
                    obscureText: !_showApiKey,
                    style: const TextStyle(color: kText, fontFamily: 'monospace', fontSize: 13),
                    decoration: const InputDecoration(hintText: 'AIzaSy…'),
                    textDirection: TextDirection.ltr,
                  )),
                  IconButton(
                    icon: Icon(_showApiKey ? Icons.visibility_off : Icons.visibility, color: kDim, size: 20),
                    onPressed: () => setState(() => _showApiKey = !_showApiKey),
                  ),
                ]),
              ],
            )),

            // Model Selection
            AppPanel(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PanelTitle('🤖 النموذج'),
                Row(children: [1, 2, 3].map((n) {
                  final active = _modelTab == n;
                  return Expanded(child: Padding(
                    padding: EdgeInsets.only(left: n < 3 ? 6 : 0),
                    child: GestureDetector(
                      onTap: () => setState(() => _modelTab = n),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          gradient: active ? const LinearGradient(colors: [kTeal, Color(0xFF0D9488)]) : null,
                          color: active ? null : kSurf2,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: active ? Colors.transparent : kBorder),
                        ),
                        child: Center(child: Text(
                          ['الوضع 1', 'الوضع 2', 'يدوي'][n - 1],
                          style: TextStyle(color: active ? Colors.white : kDim, fontSize: 13, fontWeight: active ? FontWeight.bold : FontWeight.normal),
                        )),
                      ),
                    ),
                  ));
                }).toList()),
                const SizedBox(height: 8),
                Text(_modelLabels[_modelTab] ?? '', style: const TextStyle(color: kDim, fontSize: 12, fontFamily: 'monospace')),
                if (_modelTab == 3) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _manualCtrl,
                    style: const TextStyle(color: kText, fontFamily: 'monospace'),
                    decoration: const InputDecoration(hintText: 'مثال: gemini-2.5-pro'),
                    textDirection: TextDirection.ltr,
                  ),
                ],
              ],
            )),

            // ORS API Key
            AppPanel(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PanelTitle('🗺 مفتاح ORS API (لحساب المسافات)'),
                const Text('احصل عليه مجاناً من account.heigit.org', style: TextStyle(color: kDim, fontSize: 12)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(
                    controller: _orsCtrl,
                    obscureText: !_showOrs,
                    style: const TextStyle(color: kText, fontFamily: 'monospace', fontSize: 13),
                    decoration: const InputDecoration(hintText: 'أدخل مفتاح ORS …'),
                    textDirection: TextDirection.ltr,
                  )),
                  IconButton(
                    icon: Icon(_showOrs ? Icons.visibility_off : Icons.visibility, color: kDim, size: 20),
                    onPressed: () => setState(() => _showOrs = !_showOrs),
                  ),
                ]),
              ],
            )),

            // Google Maps Key (info only — for reference)
            AppPanel(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PanelTitle('🗺 مفتاح Google Maps API'),
                const Text('يُستخدم لعرض الخريطة في المتصفح', style: TextStyle(color: kDim, fontSize: 12)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(
                    controller: _gmapsCtrl,
                    obscureText: !_showGmaps,
                    style: const TextStyle(color: kText, fontFamily: 'monospace', fontSize: 13),
                    decoration: const InputDecoration(hintText: 'AIzaSy…'),
                    textDirection: TextDirection.ltr,
                  )),
                  IconButton(
                    icon: Icon(_showGmaps ? Icons.visibility_off : Icons.visibility, color: kDim, size: 20),
                    onPressed: () => setState(() => _showGmaps = !_showGmaps),
                  ),
                ]),
              ],
            )),

            const SizedBox(height: 8),

            // Save button
            GradientButton(
              label: '✔ حفظ الإعدادات',
              onPressed: _save,
              colors: const [kTeal, Color(0xFF0D9488)],
              icon: Icons.save,
            ),

            const SizedBox(height: 16),

            // App info
            AppPanel(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PanelTitle('ℹ معلومات التطبيق'),
                _InfoRow('الإصدار', 'v1.0.0'),
                _InfoRow('النموذج الحالي', context.watch<AppConfig>().modelName),
              ],
            )),

            const SizedBox(height: 16),

            // Logout
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: kRed.withOpacity(.4)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextButton(
                onPressed: () => _confirmLogout(context),
                style: TextButton.styleFrom(
                  foregroundColor: kRed,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout, size: 18),
                    SizedBox(width: 8),
                    Text('تسجيل خروج كامل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kSurf,
        title: const Text('تسجيل الخروج', style: TextStyle(color: kText)),
        content: const Text('هل تريد تسجيل الخروج من التطبيق؟', style: TextStyle(color: kDim)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء', style: TextStyle(color: kDim))),
          TextButton(onPressed: () => Navigator.pop(context, true),  child: const Text('خروج', style: TextStyle(color: kRed))),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<AuthService>().logout();
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose(); _apiKeyCtrl.dispose();
    _orsCtrl.dispose(); _gmapsCtrl.dispose(); _manualCtrl.dispose();
    super.dispose();
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: kDim, fontSize: 13))),
      Text(value, style: const TextStyle(color: kText, fontFamily: 'monospace', fontSize: 13)),
    ]),
  );
}
