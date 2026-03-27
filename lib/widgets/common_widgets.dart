import 'package:flutter/material.dart';

// ── Colors ─────────────────────────────────────────────────────────────────
const kSky    = Color(0xFF0EA5E9);
const kCyan   = Color(0xFF06B6D4);
const kTeal   = Color(0xFF14B8A6);
const kAmber  = Color(0xFFF59E0B);
const kRed    = Color(0xFFEF4444);
const kGreen  = Color(0xFF22C55E);
const kViolet = Color(0xFF8B5CF6);
const kSurf   = Color(0xFF0B1423);
const kSurf2  = Color(0xFF0F1C30);
const kBorder = Color(0xFF1A2D45);
const kText   = Color(0xFFD8E4F0);
const kDim    = Color(0xFF6B7F96);

// ── Panel Card ─────────────────────────────────────────────────────────────
class AppPanel extends StatelessWidget {
  final Widget child;
  final Color?  accentColor;
  final EdgeInsets? padding;

  const AppPanel({super.key, required this.child, this.accentColor, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: kSurf,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor?.withOpacity(0.3) ?? kBorder),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 2))],
      ),
      padding: padding ?? const EdgeInsets.all(16),
      child: child,
    );
  }
}

// ── Panel Title ────────────────────────────────────────────────────────────
class PanelTitle extends StatelessWidget {
  final String text;
  final Color  color;
  final Widget? trailing;

  const PanelTitle(this.text, {super.key, this.color = kSky, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600,
              letterSpacing: 1.2, fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: kBorder, height: 1)),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

// ── Status Banner ──────────────────────────────────────────────────────────
enum StatusType { info, ok, warn, error, processing }

class StatusBanner extends StatelessWidget {
  final StatusType type;
  final String     message;

  const StatusBanner({super.key, required this.type, required this.message});

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return const SizedBox.shrink();
    final (color, bg, icon) = switch (type) {
      StatusType.ok         => (kGreen,  kGreen.withOpacity(.08),  Icons.check_circle_outline),
      StatusType.warn       => (kAmber,  kAmber.withOpacity(.08),  Icons.warning_amber_outlined),
      StatusType.error      => (kRed,    kRed.withOpacity(.08),    Icons.error_outline),
      StatusType.processing => (kSky,    kSky.withOpacity(.08),    Icons.hourglass_top),
      _                     => (kSky,    kSky.withOpacity(.08),    Icons.info_outline),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          if (type == StatusType.processing)
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: color))
          else
            Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: color, fontSize: 13))),
        ],
      ),
    );
  }
}

// ── Section Label ──────────────────────────────────────────────────────────
class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: kDim, fontSize: 10.5, letterSpacing: 0.8,
        fontFamily: 'monospace', fontWeight: FontWeight.w600,
      ),
    ),
  );
}

// ── Gradient Button ────────────────────────────────────────────────────────
class GradientButton extends StatelessWidget {
  final String   label;
  final VoidCallback? onPressed;
  final List<Color>   colors;
  final IconData?     icon;
  final bool          loading;
  final double        height;

  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.colors  = const [kSky, kCyan],
    this.icon,
    this.loading = false,
    this.height  = 50,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || loading;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: disabled ? [Colors.grey.shade800, Colors.grey.shade700] : colors),
          borderRadius: BorderRadius.circular(9),
          boxShadow: disabled ? [] : [
            BoxShadow(color: colors.first.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 3)),
          ],
        ),
        child: ElevatedButton(
          onPressed: disabled ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          ),
          child: loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
                    Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
        ),
      ),
    );
  }
}

// ── Outlined Button ────────────────────────────────────────────────────────
class AppOutlinedButton extends StatelessWidget {
  final String    label;
  final VoidCallback? onPressed;
  final Color     color;
  final IconData? icon;

  const AppOutlinedButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = kSky,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
          Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

// ── Info Chip ──────────────────────────────────────────────────────────────
class InfoChip extends StatelessWidget {
  final String label;
  final String value;
  const InfoChip({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: kSurf2, borderRadius: BorderRadius.circular(7),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: const TextStyle(color: kDim, fontSize: 9.5, fontFamily: 'monospace', letterSpacing: 0.7)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(color: kSky, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}

// ── Upload Zone ────────────────────────────────────────────────────────────
class UploadZone extends StatefulWidget {
  final String   hint;
  final String   subHint;
  final IconData icon;
  final Color    color;
  final VoidCallback onTap;

  const UploadZone({
    super.key,
    required this.hint,
    required this.onTap,
    this.subHint = 'xlsx · xls',
    this.icon    = Icons.upload_file,
    this.color   = kSky,
  });

  @override
  State<UploadZone> createState() => _UploadZoneState();
}

class _UploadZoneState extends State<UploadZone> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _hover = true),
      onTapUp:   (_) => setState(() => _hover = false),
      onTapCancel: ()=> setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(
          color: _hover ? widget.color.withOpacity(.1) : kSurf2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _hover ? widget.color : const Color(0xFF22385A),
            width: 1.5,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          children: [
            Icon(widget.icon, size: 36, color: widget.color.withOpacity(.7)),
            const SizedBox(height: 8),
            Text(widget.hint, style: const TextStyle(fontWeight: FontWeight.bold, color: kText)),
            const SizedBox(height: 4),
            Text(widget.subHint, style: const TextStyle(color: kDim, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// ── Spinner ────────────────────────────────────────────────────────────────
class AppSpinner extends StatelessWidget {
  final Color color;
  const AppSpinner({super.key, this.color = kSky});

  @override
  Widget build(BuildContext context) =>
      CircularProgressIndicator(strokeWidth: 2.5, color: color);
}

// ── Section Divider ────────────────────────────────────────────────────────
class SectionDivider extends StatelessWidget {
  const SectionDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      const Divider(color: kBorder, height: 24, thickness: 1);
}

// ── Badge ──────────────────────────────────────────────────────────────────
class StatusBadge extends StatelessWidget {
  final String text;
  final Color  color;
  const StatusBadge(this.text, {super.key, this.color = kSky});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(.3)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────
String formatDuration(int secs) {
  final m = secs ~/ 60;
  final s = secs  % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
