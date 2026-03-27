import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _newUserCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  bool _isAdmin      = false;
  bool _creating     = false;
  bool _loading      = false;
  String _msg        = '';
  bool   _msgOk      = false;

  List<dynamic> _users = [];

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() { _loading = true; _msg = ''; });
    try {
      final api = context.read<ApiService>();
      final users = await api.adminGetUsers();
      setState(() { _users = users; _loading = false; });
    } catch (e) {
      setState(() { _loading = false; _msg = e.toString().replaceFirst('Exception: ', ''); _msgOk = false; });
    }
  }

  Future<void> _createUser() async {
    final u = _newUserCtrl.text.trim();
    final p = _newPassCtrl.text;
    if (u.isEmpty || p.isEmpty) {
      setState(() { _msg = 'أدخل اسم المستخدم وكلمة المرور'; _msgOk = false; });
      return;
    }
    setState(() { _creating = true; _msg = ''; });
    try {
      final api = context.read<ApiService>();
      await api.adminCreateUser(u, p, _isAdmin);
      _newUserCtrl.clear(); _newPassCtrl.clear();
      setState(() { _creating = false; _msg = 'تم إنشاء المستخدم'; _msgOk = true; });
      await _loadUsers();
    } catch (e) {
      setState(() { _creating = false; _msg = e.toString().replaceFirst('Exception: ', ''); _msgOk = false; });
    }
  }

  Future<void> _setActive(int id, bool active) async {
    try {
      await context.read<ApiService>().adminSetActive(id, active);
      setState(() { _msg = active ? 'تم التفعيل' : 'تم التعطيل'; _msgOk = true; });
      await _loadUsers();
    } catch (e) {
      setState(() { _msg = e.toString().replaceFirst('Exception: ', ''); _msgOk = false; });
    }
  }

  Future<void> _resetDevice(int id) async {
    final ok = await _confirm('مسح ربط الجهاز لهذا الحساب؟');
    if (!ok) return;
    try {
      await context.read<ApiService>().adminResetDevice(id);
      setState(() { _msg = 'تم مسح ربط الجهاز'; _msgOk = true; });
      await _loadUsers();
    } catch (e) {
      setState(() { _msg = e.toString().replaceFirst('Exception: ', ''); _msgOk = false; });
    }
  }

  Future<void> _deleteUser(int id, String username) async {
    final ok = await _confirm('هل تريد حذف الحساب "$username" نهائياً؟');
    if (!ok) return;
    try {
      await context.read<ApiService>().adminDeleteUser(id);
      setState(() { _msg = 'تم حذف المستخدم'; _msgOk = true; });
      await _loadUsers();
    } catch (e) {
      setState(() { _msg = e.toString().replaceFirst('Exception: ', ''); _msgOk = false; });
    }
  }

  Future<bool> _confirm(String msg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kSurf,
        content: Text(msg, style: const TextStyle(color: kText)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء', style: TextStyle(color: kDim))),
          TextButton(onPressed: () => Navigator.pop(context, true),  child: const Text('تأكيد', style: TextStyle(color: kRed))),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('🛡️ Admin'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadUsers, tooltip: 'تحديث'),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Create user
            AppPanel(accentColor: kViolet, child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PanelTitle('➕ إنشاء مستخدم جديد', color: kViolet),
                Row(children: [
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FieldLabel('اسم المستخدم'),
                      TextField(controller: _newUserCtrl, style: const TextStyle(color: kText), decoration: const InputDecoration(hintText: 'username')),
                    ],
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FieldLabel('كلمة المرور'),
                      TextField(controller: _newPassCtrl, obscureText: true, style: const TextStyle(color: kText), decoration: const InputDecoration(hintText: 'password')),
                    ],
                  )),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Checkbox(
                    value: _isAdmin,
                    onChanged: (v) => setState(() => _isAdmin = v ?? false),
                    activeColor: kViolet,
                  ),
                  const Text('إنشاء كـ Admin', style: TextStyle(color: kText)),
                ]),
                const SizedBox(height: 8),
                if (_msg.isNotEmpty)
                  StatusBanner(type: _msgOk ? StatusType.ok : StatusType.error, message: _msg),
                GradientButton(
                  label: 'إنشاء مستخدم',
                  onPressed: _creating ? null : _createUser,
                  loading: _creating,
                  colors: const [kViolet, Color(0xFF6D28D9)],
                  icon: Icons.person_add,
                ),
              ],
            )),

            // Users list
            AppPanel(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PanelTitle('👤 المستخدمون', trailing: StatusBadge('${_users.length}', color: kDim)),
                if (_loading)
                  const Center(child: Padding(padding: EdgeInsets.all(20), child: AppSpinner()))
                else if (_users.isEmpty)
                  const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('لا يوجد مستخدمون', style: TextStyle(color: kDim))))
                else
                  ..._users.map((u) => _UserTile(
                    user: u,
                    onSetActive: (active) => _setActive(u['id'], active),
                    onResetDevice: () => _resetDevice(u['id']),
                    onDelete: () => _deleteUser(u['id'], u['username']?.toString() ?? ''),
                  )),
              ],
            )),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _newUserCtrl.dispose(); _newPassCtrl.dispose();
    super.dispose();
  }
}

class _UserTile extends StatelessWidget {
  final Map user;
  final ValueChanged<bool> onSetActive;
  final VoidCallback onResetDevice, onDelete;

  const _UserTile({required this.user, required this.onSetActive, required this.onResetDevice, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isActive = user['is_active'] != false;
    final isAdmin  = user['is_admin']  == true;
    final device   = user['device_id']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kSurf2,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: isActive ? kBorder : kRed.withOpacity(.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('#${user['id']}', style: const TextStyle(color: kDim, fontFamily: 'monospace', fontSize: 11)),
            const SizedBox(width: 10),
            Expanded(child: Text(user['username']?.toString() ?? '', style: const TextStyle(color: kText, fontWeight: FontWeight.bold, fontSize: 14))),
            if (isAdmin) const StatusBadge('admin', color: kViolet) else const SizedBox.shrink(),
            const SizedBox(width: 6),
            StatusBadge(isActive ? 'نشط' : 'معطّل', color: isActive ? kGreen : kRed),
          ]),
          if (device.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Device: $device', style: const TextStyle(color: kDim, fontFamily: 'monospace', fontSize: 10), overflow: TextOverflow.ellipsis),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            _ActionBtn(label: isActive ? 'تعطيل' : 'تفعيل', color: isActive ? kAmber : kGreen, onPressed: () => onSetActive(!isActive)),
            _ActionBtn(label: 'مسح الجهاز', color: kTeal, onPressed: onResetDevice),
            _ActionBtn(label: 'حذف', color: kRed, onPressed: onDelete),
          ]),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label; final Color color; final VoidCallback onPressed;
  const _ActionBtn({required this.label, required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      foregroundColor: color, side: BorderSide(color: color),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
  );
}
