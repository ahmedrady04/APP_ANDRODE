import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import '../config.dart';
import '../services/auth_service.dart';
import '../widgets/common_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl   = TextEditingController();
  final _passCtrl   = TextEditingController();
  final _deviceCtrl = TextEditingController();
  final _urlCtrl    = TextEditingController();

  bool   _loading    = false;
  bool   _showPass   = false;
  String _errorMsg   = '';

  @override
  void initState() {
    super.initState();
    _loadDeviceId();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cfg = context.read<AppConfig>();
      _urlCtrl.text = cfg.backendUrl;
    });
  }

  Future<void> _loadDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var did = prefs.getString('device_id') ?? '';
    if (did.isEmpty) {
      did = 'dev-${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('device_id', did);
    }
    setState(() => _deviceCtrl.text = did);
  }

  Future<void> _login() async {
    final user   = _userCtrl.text.trim();
    final pass   = _passCtrl.text;
    final device = _deviceCtrl.text.trim();

    if (user.isEmpty || pass.isEmpty) {
      setState(() => _errorMsg = 'أدخل اسم المستخدم وكلمة المرور');
      return;
    }

    // Save backend URL
    final cfg = context.read<AppConfig>();
    cfg.update(url: _urlCtrl.text.trim());
    await cfg.save();

    setState(() { _loading = true; _errorMsg = ''; });

    final auth = context.read<AuthService>();
    final err  = await auth.login(user, pass, device);

    if (mounted) {
      setState(() { _loading = false; _errorMsg = err ?? ''; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              // Logo
              Center(
                child: Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF38BDF8), kSky, Color(0xFF0284C7)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(color: kSky.withOpacity(.4), blurRadius: 20)],
                  ),
                  child: const Center(child: Text('🚗', style: TextStyle(fontSize: 36))),
                ),
              ),
              const SizedBox(height: 20),
              const Center(
                child: Text(
                  'التفريغ',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: kSky),
                ),
              ),
              const Center(
                child: Text(
                  'License Plate Extractor · GPS · MP3',
                  style: TextStyle(color: kDim, fontSize: 13, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 40),

              // Backend URL
              AppPanel(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('رابط الخادم (Railway)'),
                  TextFormField(
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

              const SizedBox(height: 4),

              // Login form
              AppPanel(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PanelTitle('تسجيل الدخول'),
                  const FieldLabel('اسم المستخدم'),
                  TextFormField(
                    controller: _userCtrl,
                    style: const TextStyle(color: kText),
                    decoration: const InputDecoration(
                      hintText: 'username',
                      prefixIcon: Icon(Icons.person_outline, color: kDim, size: 18),
                    ),
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  ),
                  const SizedBox(height: 12),
                  const FieldLabel('كلمة المرور'),
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: !_showPass,
                    style: const TextStyle(color: kText),
                    decoration: InputDecoration(
                      hintText: 'password',
                      prefixIcon: const Icon(Icons.lock_outline, color: kDim, size: 18),
                      suffixIcon: IconButton(
                        icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility, color: kDim, size: 18),
                        onPressed: () => setState(() => _showPass = !_showPass),
                      ),
                    ),
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _login(),
                  ),
                  const SizedBox(height: 12),
                  const FieldLabel('Device ID'),
                  TextFormField(
                    controller: _deviceCtrl,
                    style: const TextStyle(color: kDim, fontFamily: 'monospace', fontSize: 12),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.phone_android, color: kDim, size: 18),
                    ),
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(height: 20),
                  if (_errorMsg.isNotEmpty)
                    StatusBanner(type: StatusType.error, message: _errorMsg),
                  GradientButton(
                    label: 'دخول',
                    onPressed: _loading ? null : _login,
                    loading: _loading,
                    colors: const [kSky, kCyan],
                    icon: Icons.login,
                  ),
                ],
              )),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _userCtrl.dispose(); _passCtrl.dispose();
    _deviceCtrl.dispose(); _urlCtrl.dispose();
    super.dispose();
  }
}
