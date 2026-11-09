import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/state.dart';
import '../core/theme.dart';

class Logo extends StatelessWidget {
  const Logo({super.key, this.size = 36});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _LogoPainter()),
      );
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final k = s.width / 48;
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(14 * k)), Paint()..color = const Color(0xFF0F5C5A));
    final p = Path()
      ..moveTo(11 * k, 35 * k)
      ..lineTo(19 * k, 35 * k)
      ..lineTo(19 * k, 27.5 * k)
      ..lineTo(27 * k, 27.5 * k)
      ..lineTo(27 * k, 20 * k)
      ..lineTo(36 * k, 20 * k);
    canvas.drawPath(p, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(Offset(36 * k, 12.5 * k), 3.6 * k, Paint()..color = const Color(0xFFF6C453));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Quick-exit button: on every learner screen. Instantly swaps to a neutral
/// calculator screen and locks the app.
class QuickExitButton extends StatelessWidget {
  const QuickExitButton({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final c = NsColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: s.t('app', 'quick_exit'),
        child: FilledButton.icon(
          key: const Key('quick-exit'),
          style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: c.onAccent,
              padding: const EdgeInsets.symmetric(horizontal: 12), minimumSize: const Size(44, 44)),
          onPressed: s.quickExit,
          icon: const Icon(Icons.close_rounded, size: 20),
          label: Text(s.t('app', 'quick_exit')),
        ),
      ),
    );
  }
}

class NsScaffold extends StatelessWidget {
  const NsScaffold({super.key, required this.title, required this.body, this.actions = const [], this.quickExit = true,
      this.showLogo = false, this.bottom, this.fab});
  final String title;
  final Widget body;
  final List<Widget> actions;
  final bool quickExit, showLogo;
  final Widget? bottom, fab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          if (showLogo) ...[const Logo(size: 32), const SizedBox(width: 10)],
          Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
        ]),
        actions: [...actions, if (quickExit) const QuickExitButton()],
      ),
      body: SafeArea(child: body),
      bottomNavigationBar: bottom,
      floatingActionButton: fab,
    );
  }
}

/// Constrains content to a readable width on web/tablet.
class NsPage extends StatelessWidget {
  const NsPage({super.key, required this.children, this.maxWidth = 640, this.padding = const EdgeInsets.all(16)});
  final List<Widget> children;
  final double maxWidth;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: ListView(padding: padding, children: children),
        ),
      );
}

class Chip2 extends StatelessWidget {
  const Chip2(this.label, {super.key, required this.bg, required this.fg});
  final String label;
  final Color bg, fg;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
      );
}

class DraftChip extends StatelessWidget {
  const DraftChip({super.key});
  @override
  Widget build(BuildContext context) =>
      const Chip2('DRAFT · clinician review', bg: Color(0xFFF6C453), fg: Color(0xFF1B1F23));
}

class DemoTag extends StatelessWidget {
  const DemoTag({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = NsColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(8)),
      child: Text(s.t('extra', 'referral_demo_tag'), style: TextStyle(color: c.onAccent, fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }
}

class Bubble extends StatelessWidget {
  const Bubble({super.key, required this.child, this.safety = false, this.user = false});
  final Widget child;
  final bool safety, user;
  @override
  Widget build(BuildContext context) {
    final c = NsColors.of(context);
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          color: user ? c.primaryTint : c.surface,
          borderRadius: user
              ? const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(4), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16))
              : const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
          border: Border.all(color: safety ? c.support : c.line, width: safety ? 2 : 1),
        ),
        child: child,
      ),
    );
  }
}

/// "Sources" line that expands to show where an answer came from.
class SourcesLine extends StatefulWidget {
  const SourcesLine({super.key, required this.sources});
  final List sources;
  @override
  State<SourcesLine> createState() => _SourcesLineState();
}

class _SourcesLineState extends State<SourcesLine> {
  bool open = false;
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = NsColors.of(context);
    if (widget.sources.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        onTap: () => setState(() => open = !open),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: c.text2),
            Text('${s.t('app', 'sources')} (${widget.sources.length})', style: TextStyle(fontSize: 13, color: c.text2, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
      if (open)
        for (final src in widget.sources)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              '• ${src['source_document']}${(src['source_section'] ?? '') != '' ? ' — ${src['source_section']}' : ''}\n  ${src['review_status']}',
              style: TextStyle(fontSize: 12, color: c.text2),
            ),
          ),
    ]);
  }
}

class NotMedicalAdvice extends StatelessWidget {
  const NotMedicalAdvice({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(s.t('app', 'not_medical_advice'),
          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: NsColors.of(context).text2)),
    );
  }
}

class BigTile extends StatelessWidget {
  const BigTile({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap, this.tileKey});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  final Key? tileKey;
  @override
  Widget build(BuildContext context) {
    final c = NsColors.of(context);
    return Card(
      key: tileKey,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: c.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: c.primary)),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
            Icon(Icons.chevron_right, color: c.text2),
          ]),
        ),
      ),
    );
  }
}
