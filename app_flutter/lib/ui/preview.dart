import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/state.dart';
import '../screens/lock.dart';
import '../widgets/chat_ui.dart';
import 'kit.dart';

/// STATIC screens for design approval (step 1). No logic, no network: sample data only.
/// Reached at /#/preview and /#/preview/NAME. Removed once wired to the real logic.
const previewScreens = [
  'consent', 'age', 'under15', 'language', 'pin', 'home', 'ask', 'check', 'result',
  'services', 'service', 'code', 'settings', 'crisis', 'exit', 'student',
];

class PreviewIndex extends StatelessWidget {
  const PreviewIndex({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: nsBar(title: 'Screens for approval'),
        body: NsBody(children: [
          RowGroup(rows: [for (final n in previewScreens) NsRow(title: n, onTap: () => context.go('/preview/$n'))]),
        ]),
      );
}

class PreviewScreen extends StatelessWidget {
  const PreviewScreen({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    String t(String f, String k, [Map? p]) => s.t([f, k], p);
    void nop() {}
    final exit = quickExitIcon(nop, t('app', 'quick_exit'));
    final back = nop;

    switch (name) {
      // ------------------------------------------------ first-time setup
      case 'consent':
        return Scaffold(
          appBar: nsBar(title: 'NextStep', brand: true),
          body: NsBody(
            bottom: PrimaryButton(t('consent', 'btn_agree'), onPressed: nop),
            children: [Panel(child: Text(t('consent', 'body'), style: bodyText))],
          ),
        );
      case 'age':
        return Scaffold(
          appBar: nsBar(title: 'NextStep', brand: true),
          body: NsBody(children: [
            Text(t('age', 'ask'), style: titleText),
            const SizedBox(height: 16),
            ChoiceButton(t('age', 'btn_15_17'), onPressed: nop),
            ChoiceButton(t('age', 'btn_18_24'), onPressed: nop),
            ChoiceButton(t('age', 'btn_under15'), onPressed: nop),
          ]),
        );
      case 'under15':
        return Scaffold(
          appBar: nsBar(title: 'NextStep', brand: true),
          body: NsBody(children: [Panel(border: W.berry, child: Text(t('age', 'under15'), style: bodyText))]),
        );
      case 'language':
        return Scaffold(
          appBar: nsBar(title: 'NextStep', brand: true),
          body: NsBody(children: [
            Text(t('menu', 'lang_prompt'), style: titleText),
            const SizedBox(height: 16),
            ChoiceButton(t('menu', 'btn_en'), onPressed: nop),
            ChoiceButton(t('menu', 'btn_pcm'), onPressed: nop),
          ]),
        );

      // ------------------------------------------------ returning user
      case 'pin':
        return Scaffold(
          appBar: nsBar(title: 'NextStep', brand: true),
          body: NsBody(children: [
            Center(child: Text(t('app', 'unlock_title'), style: titleText)),
            const SizedBox(height: 12),
            const _StaticPinPad(),
          ]),
        );

      // ------------------------------------------------ home
      case 'home':
        return Scaffold(
          appBar: nsBar(title: 'NextStep', brand: true, actions: [
            exit,
            IconButton(tooltip: t('app', 'settings_title'), onPressed: nop, icon: const Icon(Icons.settings_outlined, color: W.ink)),
          ]),
          body: NsBody(children: [
            RowGroup(rows: [
              NsRow(title: t('menu', 'row_ask'), subtitle: t('menu', 'row_ask_desc'), onTap: nop),
              NsRow(title: t('menu', 'row_check'), subtitle: t('menu', 'row_check_desc'), onTap: nop),
              NsRow(title: t('menu', 'row_find'), subtitle: t('menu', 'row_find_desc'), onTap: nop),
            ]),
            const SizedBox(height: 16),
            Panel(
              child: InkWell(
                onTap: nop,
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t('app', 'code_title'), style: const TextStyle(fontSize: 13, color: W.sub)),
                      const Text('PXWX6H', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 3, color: W.berry)),
                      const Text('[DEMO] Youth Health Service A · Yaba', style: TextStyle(fontSize: 13, color: W.sub)),
                    ]),
                  ),
                  const Icon(Icons.chevron_right, color: W.sub),
                ]),
              ),
            ),
          ]),
        );

      // ------------------------------------------------ ask (the chat design, with a back arrow)
      case 'ask':
        return Scaffold(
          backgroundColor: W.bg,
          appBar: nsBar(title: 'NextStep', brand: true, onBack: back, actions: [exit]),
          body: Column(children: [
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(10, 12, 10, 16), children: [
                BotBubble(text: t('qa', 'prompt')),
                const SizedBox(height: 8),
                UserBubble(t('qa', 'user_voice')),
                const SizedBox(height: 8),
                BotBubble(text: t('qa', 'answer_kiss'), draft: true, buttons: [
                  ReplyRow(label: t('qa', 'btn_protect'), onTap: nop),
                  ReplyRow(label: t('qa', 'btn_another'), onTap: nop),
                ]),
              ]),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 14),
              child: Row(children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                    child: Text(t('sim', 'placeholder'), style: const TextStyle(color: W.sub, fontSize: 15)),
                  ),
                ),
                const SizedBox(width: 6),
                Container(width: 46, height: 46, decoration: const BoxDecoration(color: W.berry, shape: BoxShape.circle),
                    child: const Icon(Icons.mic_none, color: Colors.white, size: 20)),
              ]),
            ),
          ]),
        );

      // ------------------------------------------------ private check
      case 'check':
        return Scaffold(
          appBar: nsBar(title: t('menu', 'row_check'), onBack: back, actions: [exit]),
          body: NsBody(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: const LinearProgressIndicator(value: 2 / 6, minHeight: 6, color: W.berry, backgroundColor: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(t('check', 'progress', {'n': '2'}), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: W.berry)),
            const SizedBox(height: 12),
            Text(t('check', 'q2'), style: titleText),
            const SizedBox(height: 20),
            ChoiceButton(t('check', 'btn_yes'), onPressed: nop),
            ChoiceButton(t('check', 'btn_no'), onPressed: nop),
            ChoiceButton(t('check', 'btn_not_sure'), onPressed: nop),
          ]),
        );
      case 'result':
        return Scaffold(
          appBar: nsBar(title: t('menu', 'row_check'), onBack: back, actions: [exit]),
          body: NsBody(
            bottom: PrimaryButton(t('check', 'btn_find'), onPressed: nop),
            children: [Panel(child: Text(t('check', 'result_next'), style: bodyText))],
          ),
        );

      // ------------------------------------------------ find a service
      case 'services':
        return Scaffold(
          appBar: nsBar(title: t('menu', 'row_find'), onBack: back, actions: [exit]),
          body: NsBody(children: [
            RowGroup(rows: [
              for (final (n, a) in [('A', 'Yaba · Lagos Mainland'), ('C', 'Surulere'), ('D', 'Ikeja'), ('F', 'Ikorodu')])
                NsRow(title: '[DEMO] Youth Health Service $n', subtitle: a, onTap: nop),
            ]),
          ]),
        );
      case 'service':
        return Scaffold(
          appBar: nsBar(title: t('menu', 'row_find'), onBack: back, actions: [exit]),
          body: NsBody(
            bottom: PrimaryButton(t('app', 'get_code'), onPressed: nop),
            children: [
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: W.shadow),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  ServiceCardTop(free: t('referral', 'tag_free'), youth: t('referral', 'tag_youth'), label: t('referral', 'card_image_label')),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: DefaultTextStyle(
                      style: const TextStyle(fontSize: 15, height: 20 / 15, color: W.ink),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Tag(t('extra', 'referral_demo_tag'), bg: const Color(0xFFC2462E), fg: Colors.white),
                        const SizedBox(height: 8),
                        const Text('[DEMO] Youth Health Service A', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        const Row(children: [Icon(Icons.place_outlined, size: 18, color: W.berry), SizedBox(width: 6), Text('[STREET ADDRESS], Yaba')]),
                        const SizedBox(height: 6),
                        const Row(children: [Icon(Icons.schedule, size: 18, color: W.berry), SizedBox(width: 6), Text('[DAYS], [HOURS]')]),
                        const SizedBox(height: 10),
                        Text(t('referral', 'expect_title'), style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(t('referral', 'expect')),
                      ]),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        );

      // ------------------------------------------------ referral code
      case 'code':
        return Scaffold(
          appBar: nsBar(title: t('app', 'code_title'), onBack: back, actions: [exit]),
          body: NsBody(
            bottom: PrimaryButton(t('app', 'back_home'), onPressed: nop),
            children: [
              Panel(
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 14),
                child: Column(children: [
                  const Text('PXWX6H', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: 8, color: W.berry)),
                  const SizedBox(height: 12),
                  Text(t('app', 'code_how'), textAlign: TextAlign.center, style: bodyText),
                ]),
              ),
            ],
          ),
        );

      // ------------------------------------------------ settings
      case 'settings':
        return Scaffold(
          appBar: nsBar(title: t('app', 'settings_title'), onBack: back, actions: [exit]),
          body: NsBody(children: [
            RowGroup(rows: [
              NsRow(title: t('app', 'language'), trailing: const Text('English', style: TextStyle(color: W.sub)), onTap: nop),
              NsRow(title: t('app', 'pin_lock'), trailing: Switch(value: false, onChanged: (_) {}, activeThumbColor: W.berry)),
              NsRow(title: t('app', 'low_data'), trailing: Switch(value: false, onChanged: (_) {}, activeThumbColor: W.berry)),
              NsRow(title: t('app', 'delete'), trailing: const SizedBox.shrink(), onTap: nop),
            ]),
            const SizedBox(height: 28),
            Center(child: TextButton(onPressed: nop, child: Text(t('app', 'staff_signin'), style: const TextStyle(color: W.sub, fontSize: 13)))),
          ]),
        );

      // ------------------------------------------------ crisis
      case 'crisis':
        return Scaffold(
          appBar: nsBar(title: t('app', 'crisis_title'), onBack: back, actions: [exit]),
          body: NsBody(
            bottom: PrimaryButton(t('app', 'call_helpline'), onPressed: nop),
            children: [Panel(border: W.berry, child: Text(t('crisis', 'violence'), style: bodyText))],
          ),
        );

      // ------------------------------------------------ quick exit
      case 'exit':
        return const NeutralScreen();

      // ------------------------------------------------ student question page (QR link)
      case 'student':
        return Scaffold(
          backgroundColor: W.bg,
          appBar: nsBar(title: 'NextStep', brand: true),
          body: Column(children: [
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(10, 12, 10, 16), children: [
                BotBubble(text: t('app', 'join_body')),
              ]),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 14),
              child: Row(children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                    child: Text(t('sim', 'placeholder'), style: const TextStyle(color: W.sub, fontSize: 15)),
                  ),
                ),
                const SizedBox(width: 6),
                Container(width: 46, height: 46, decoration: const BoxDecoration(color: W.berry, shape: BoxShape.circle),
                    child: const Icon(Icons.send, color: Colors.white, size: 20)),
              ]),
            ),
          ]),
        );
    }
    return const PreviewIndex();
  }
}

class _StaticPinPad extends StatelessWidget {
  const _StaticPinPad();
  @override
  Widget build(BuildContext context) => Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < 4; i++)
            Container(margin: const EdgeInsets.all(8), width: 14, height: 14,
                decoration: BoxDecoration(shape: BoxShape.circle, color: i < 2 ? W.berry : Colors.white)),
        ]),
        const SizedBox(height: 12),
        for (final row in [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9'], ['', '0', '⌫']])
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final d in row)
              Padding(
                padding: const EdgeInsets.all(6),
                child: SizedBox(
                  width: 76,
                  height: 56,
                  child: d.isEmpty
                      ? null
                      : OutlinedButton(
                          style: OutlinedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: W.ink,
                              side: const BorderSide(color: W.btnLine), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          onPressed: () {},
                          child: Text(d, style: const TextStyle(fontSize: 22)),
                        ),
                ),
              ),
          ]),
      ]);
}
