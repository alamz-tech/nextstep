import 'package:flutter/material.dart';

import '../widgets/chat_ui.dart';

/// Minimal building blocks for every non-chat screen, in the chat-frame design's style:
/// white top bar, warm grey background, white rounded panels, berry for the one action.

/// Top bar. Back arrow (inner screens) or app name (Home), plus optional icons on the right.
PreferredSizeWidget nsBar({String? title, VoidCallback? onBack, List<Widget> actions = const [], bool brand = false}) => PreferredSize(
      preferredSize: const Size.fromHeight(57),
      child: Container(
        decoration: const BoxDecoration(color: W.header, border: Border(bottom: BorderSide(color: W.headerLine))),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
            child: Row(children: [
              if (onBack != null)
                IconButton(key: const Key('back'), tooltip: 'Back', onPressed: onBack, icon: const Icon(Icons.arrow_back, color: W.ink))
              else
                const SizedBox(width: 8),
              if (brand) ...[const Avatar(), const SizedBox(width: 10)],
              Expanded(
                child: Text(title ?? '', overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: W.ink)),
              ),
              ...actions,
            ]),
          ),
        ),
      ),
    );

/// Quick-exit icon for the top bar of every learner screen.
Widget quickExitIcon(VoidCallback onExit, String label) => IconButton(
      key: const Key('quick-exit'),
      tooltip: label,
      onPressed: onExit,
      icon: const Icon(Icons.exit_to_app, color: W.ink),
    );

/// Page body: warm grey background, content centred at phone width.
class NsBody extends StatelessWidget {
  const NsBody({super.key, required this.children, this.bottom});
  final List<Widget> children;
  final Widget? bottom;
  @override
  Widget build(BuildContext context) => Container(
        color: W.bg,
        child: SafeArea(
          top: false,
          child: Column(children: [
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ListView(padding: const EdgeInsets.fromLTRB(12, 16, 12, 16), children: children),
                ),
              ),
            ),
            if (bottom != null)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 16), child: bottom),
                ),
              ),
          ]),
        ),
      );
}

/// White panel, same corner and shadow as the chat bubbles.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.border});
  final Widget child;
  final EdgeInsets padding;
  final Color? border;
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: W.shadow,
            border: border == null ? null : Border.all(color: border!, width: 2)),
        child: child,
      );
}

/// A group of tappable rows inside one white panel (like the design's list sheet).
class RowGroup extends StatelessWidget {
  const RowGroup({super.key, required this.rows});
  final List<Widget> rows;
  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: W.shadow),
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1, color: W.btnLine),
            rows[i],
          ],
        ]),
      );
}

class NsRow extends StatelessWidget {
  const NsRow({super.key, required this.title, this.subtitle, this.onTap, this.trailing});
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title, style: const TextStyle(fontSize: 16, color: W.ink)),
                if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 13, color: W.sub)),
              ]),
            ),
            trailing ?? (onTap != null ? const Icon(Icons.chevron_right, color: W.sub) : const SizedBox.shrink()),
          ]),
        ),
      );
}

/// The one primary action on a screen.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton(this.label, {super.key, required this.onPressed, this.color = W.berry});
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: color, shape: const StadiumBorder(),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          onPressed: onPressed,
          child: Text(label),
        ),
      );
}

/// Plain choice button (for answers like 15–17 / 18–24): white, berry text.
class ChoiceButton extends StatelessWidget {
  const ChoiceButton(this.label, {super.key, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SizedBox(
          height: 48,
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: W.berry, shape: const StadiumBorder(),
                side: const BorderSide(color: W.btnLine), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            onPressed: onPressed,
            child: Text(label),
          ),
        ),
      );
}

const bodyText = TextStyle(fontSize: 15.5, height: 21 / 15.5, color: W.ink);
const titleText = TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: W.ink, height: 1.3);
