import 'dart:math';

import 'package:flutter/material.dart';

/// Colours and shapes from the design board "Component · WhatsApp-style chat frame".
class W {
  static const bg = Color(0xFFEAE6DF);
  static const header = Color(0xFFFFFFFF);
  static const headerLine = Color(0xFFE3E0DA);
  static const ink = Color(0xFF111B21);
  static const sub = Color(0xFF54656F);
  static const user = Color(0xFFFBE4EC); // blush: learner's own bubbles
  static const bot = Color(0xFFFFFFFF);
  static const btnLine = Color(0xFFE9EDEF);
  static const link = Color(0xFFA3305A); // berry: reply buttons
  static const teal = Color(0xFF0F5C5A); // kept for the service card
  static const berry = Color(0xFFA3305A); // logo, mic/send, accents
  static const berryDeep = Color(0xFF6E1F3D);
  static const yellow = Color(0xFFF6C453);
  static const blue = Color(0xFF2F5DA8);
  static const pillYellow = Color(0xFFFFF5C4);
  static const pillYellowInk = Color(0xFF54470F);
  static const shadow = [BoxShadow(color: Color(0x21000000), offset: Offset(0, 1), blurRadius: 0.5)];
}

/// Teal circle with the NextStep steps mark (header avatar).
class Avatar extends StatelessWidget {
  const Avatar({super.key, this.size = 38});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(color: W.berry, shape: BoxShape.circle),
        child: CustomPaint(painter: StepsMark(stroke: Colors.white, dot: W.yellow, scale: 26 / 38)),
      );
}

class StepsMark extends CustomPainter {
  StepsMark({required this.stroke, required this.dot, this.scale = 1, this.tile});
  final Color stroke, dot;
  final Color? tile;
  final double scale;
  @override
  void paint(Canvas c, Size s) {
    final box = s.width * scale;
    final o = Offset((s.width - box) / 2, (s.height - box) / 2);
    final k = box / 48;
    if (tile != null) {
      c.drawRRect(RRect.fromRectAndRadius(o & Size(box, box), Radius.circular(14 * k)), Paint()..color = tile!);
    }
    final p = Path()
      ..moveTo(o.dx + 11 * k, o.dy + 35 * k)
      ..lineTo(o.dx + 19 * k, o.dy + 35 * k)
      ..lineTo(o.dx + 19 * k, o.dy + 27.5 * k)
      ..lineTo(o.dx + 27 * k, o.dy + 27.5 * k)
      ..lineTo(o.dx + 27 * k, o.dy + 20 * k)
      ..lineTo(o.dx + 36 * k, o.dy + 20 * k);
    c.drawPath(p, Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = (tile == null ? 4.5 : 4) * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
    c.drawCircle(Offset(o.dx + 36 * k, o.dy + 12.5 * k), (tile == null ? 3.8 : 3.6) * k, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// White header: avatar, "NextStep", overflow menu.
PreferredSizeWidget chatHeader({required List<PopupMenuEntry<String>> menu, required void Function(String) onMenu, Widget? leading}) =>
    PreferredSize(
      preferredSize: const Size.fromHeight(57),
      child: Container(
        decoration: const BoxDecoration(color: W.header, border: Border(bottom: BorderSide(color: W.headerLine))),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
            child: Row(children: [
              if (leading != null) leading,
              const Avatar(),
              const SizedBox(width: 10),
              const Expanded(child: Text('NextStep', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: W.ink))),
              if (menu.isNotEmpty)
                PopupMenuButton<String>(
                  key: const Key('chat-menu'),
                  icon: const Icon(Icons.more_vert, color: W.ink),
                  onSelected: onMenu,
                  itemBuilder: (_) => menu,
                ),
            ]),
          ),
        ),
      ),
    );

class SysPill extends StatelessWidget {
  const SysPill(this.text, {super.key, this.yellow = false});
  final String text;
  final bool yellow;
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          margin: EdgeInsets.symmetric(vertical: yellow ? 0 : 6),
          padding: EdgeInsets.symmetric(horizontal: yellow ? 10 : 12, vertical: yellow ? 6 : 5),
          decoration: BoxDecoration(color: yellow ? W.pillYellow : Colors.white, borderRadius: BorderRadius.circular(8)),
          child: Text(text, textAlign: TextAlign.center,
              style: TextStyle(fontSize: yellow ? 12 : 13, height: 16 / 12, color: yellow ? W.pillYellowInk : W.sub, fontWeight: yellow ? FontWeight.w400 : FontWeight.w500)),
        ),
      );
}

class UserBubble extends StatelessWidget {
  const UserBubble(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 290),
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 6),
          decoration: const BoxDecoration(color: W.user, boxShadow: W.shadow,
              borderRadius: BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(2), bottomLeft: Radius.circular(10), bottomRight: Radius.circular(10))),
          child: Text(text, style: const TextStyle(fontSize: 15.5, height: 21 / 15.5, color: W.ink)),
        ),
      );
}

List<double> bars(int n, double seed) => List.generate(n, (i) => 6 + (sin((i + 1) * seed).abs() * 20).roundToDouble());

class Waveform extends StatelessWidget {
  const Waveform({super.key, required this.n, required this.seed, required this.color});
  final int n;
  final double seed;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 28,
        child: Row(children: [
          for (final h in bars(n, seed))
            Container(width: 3, height: h, margin: const EdgeInsets.only(right: 2),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        ]),
      );
}

class UserVoiceBubble extends StatelessWidget {
  const UserVoiceBubble({super.key, required this.transcript});
  final String transcript;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            width: 260,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: const BoxDecoration(color: W.user, boxShadow: W.shadow,
                borderRadius: BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(2), bottomLeft: Radius.circular(10), bottomRight: Radius.circular(10))),
            child: const Row(children: [
              Icon(Icons.play_arrow, color: W.sub, size: 26),
              SizedBox(width: 10),
              Expanded(child: ClipRect(child: Waveform(n: 28, seed: 1.7, color: Color(0xFF7C8C95)))),
              SizedBox(width: 10),
              Text('0:04', style: TextStyle(fontSize: 12, color: W.sub)),
            ]),
          ),
        ]),
      );
}

class BotVoiceBubble extends StatelessWidget {
  const BotVoiceBubble({super.key, required this.label, required this.onPlay});
  final String label;
  final VoidCallback onPlay;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 270,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: const BoxDecoration(color: W.bot, boxShadow: W.shadow,
              borderRadius: BorderRadius.only(topLeft: Radius.circular(2), topRight: Radius.circular(10), bottomLeft: Radius.circular(10), bottomRight: Radius.circular(10))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(width: 36, height: 36, decoration: const BoxDecoration(color: W.berry, shape: BoxShape.circle),
                  child: const Icon(Icons.mic_none, color: Colors.white, size: 18)),
              IconButton(onPressed: onPlay, icon: const Icon(Icons.play_arrow, color: W.sub), tooltip: label),
              const Expanded(child: ClipRect(child: Waveform(n: 24, seed: 2.3, color: W.berry))),
            ]),
            Align(alignment: Alignment.centerRight, child: Text(label, style: const TextStyle(fontSize: 12, color: W.sub))),
          ]),
        ),
      );
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, required this.bg, required this.fg});
  final String text;
  final Color bg, fg;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      );
}

/// One reply-button row inside a bot bubble (WhatsApp style).
class ReplyRow extends StatelessWidget {
  const ReplyRow({super.key, required this.label, this.onTap, this.icon});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: W.btnLine))),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (icon != null) ...[Icon(icon, size: 18, color: onTap == null ? W.link.withValues(alpha: 0.45) : W.link), const SizedBox(width: 8)],
            Flexible(
              child: Text(label, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: onTap == null ? W.link.withValues(alpha: 0.45) : W.link)),
            ),
          ]),
        ),
      );
}

/// White bot bubble with optional service card header, kicker, text, reply rows and chips.
class BotBubble extends StatelessWidget {
  const BotBubble({super.key, required this.text, this.kicker, this.card, this.buttons = const [], this.draft = false, this.safety = false,
      this.draftLabel = 'DRAFT · clinician review', this.safetyLabel = 'SAFETY RESPONSE · logged as count only'});
  final String text;
  final String? kicker;
  final Widget? card;
  final List<Widget> buttons;
  final bool draft, safety;
  final String draftLabel, safetyLabel;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 310),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(color: W.bot, boxShadow: W.shadow,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(2), topRight: Radius.circular(10), bottomLeft: Radius.circular(10), bottomRight: Radius.circular(10))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (card != null) card!,
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (kicker != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(kicker!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: W.berry, letterSpacing: 0.3)),
                      ),
                    if (text.isNotEmpty) Text(text, style: const TextStyle(fontSize: 15.5, height: 21 / 15.5, color: W.ink)),
                  ]),
                ),
                ...buttons,
              ]),
            ),
            if (draft || safety)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(spacing: 6, children: [
                  if (draft) Tag(draftLabel, bg: W.yellow, fg: const Color(0xFF1B1F23)),
                  if (safety) Tag(safetyLabel, bg: W.blue, fg: Colors.white),
                ]),
              ),
          ]),
        ),
      );
}

/// Service card header + details (design: referral card).
class ServiceCardTop extends StatelessWidget {
  const ServiceCardTop({super.key, required this.free, required this.youth, required this.label});
  final String? free, youth;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(4, 4, 4, 0),
        height: 140,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: W.teal, borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 34, height: 34, child: CustomPaint(painter: StepsMark(stroke: W.berry, dot: W.yellow, tile: Colors.white))),
            const Spacer(),
            if (free != null) Tag(free!, bg: W.yellow, fg: const Color(0xFF1B1F23)),
            const SizedBox(width: 6),
            if (youth != null) Tag(youth!, bg: Colors.white, fg: W.teal),
          ]),
          Text(label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
        ]),
      );
}

/// WhatsApp-style list sheet with radio rings.
Future<String?> showListSheet(BuildContext context, {required String title, required List<(String id, String title, String desc)> rows}) =>
    showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: W.btnLine))),
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: W.ink, fontSize: 16)),
          ),
          for (final r in rows)
            InkWell(
              key: Key('row-${r.$1}'),
              onTap: () => Navigator.pop(ctx, r.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F2F5)))),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.$2, style: const TextStyle(fontSize: 15.5, color: W.ink)),
                      Text(r.$3, style: const TextStyle(fontSize: 13, color: W.sub)),
                    ]),
                  ),
                  Container(width: 18, height: 18,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF8696A0), width: 2))),
                ]),
              ),
            ),
        ]),
      ),
    );
