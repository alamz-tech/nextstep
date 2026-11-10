// App behaviour tests (red-team app_cases): setup, Home hub, quick exit, PIN, storage.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextstep/core/state.dart';
import 'package:nextstep/main.dart';
import 'package:provider/provider.dart';

Future<AppState> boot(WidgetTester t, {Map<String, String> stored = const {}}) async {
  FlutterSecureStorage.setMockInitialValues(Map.of(stored));
  final s = AppState();
  await t.runAsync(s.init);
  await t.pumpWidget(ChangeNotifierProvider.value(value: s, child: const NextStepApp()));
  await t.pump(const Duration(milliseconds: 100));
  return s;
}

Future<AppState> bootSetUp(WidgetTester t) async {
  final s = await boot(t);
  await t.runAsync(() => s.finishSetup('18_24', 'en'));
  await t.pumpAndSettle();
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('nextstep/privacy'), (_) async => null));

  testWidgets('first open shows setup, not the chat; setup leads to Home', (t) async {
    final s = await boot(t);
    expect(find.byKey(const Key('consent-agree')), findsOneWidget);
    expect(find.byKey(const Key('chat-input')), findsNothing);
    await t.tap(find.byKey(const Key('consent-agree')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('age-18_24')));
    await t.pumpAndSettle();
    await t.runAsync(() async {
      await t.tap(find.byKey(const Key('lang-en')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pumpAndSettle();
    expect(s.setupDone, isTrue);
    for (final k in ['home-ask', 'home-check', 'home-find', 'quick-exit', 'settings']) {
      expect(find.byKey(Key(k)), findsOneWidget, reason: k);
    }
    expect(find.byKey(const Key('home-code')), findsNothing); // only once a code exists
  });

  testWidgets('under-15 exit saves nothing', (t) async {
    final s = await boot(t);
    await t.tap(find.byKey(const Key('consent-agree')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('age-under_15')));
    await t.pumpAndSettle();
    expect(s.setupDone, isFalse);
    expect(await s.store.readJson('prefs'), isNull);
  });

  testWidgets('quick exit shows a neutral calculator with no NextStep text', (t) async {
    await bootSetUp(t);
    await t.tap(find.byKey(const Key('quick-exit')));
    await t.pumpAndSettle();
    expect(find.text('Calculator'), findsOneWidget);
    expect(find.textContaining('NextStep'), findsNothing);
    expect(find.textContaining('HIV'), findsNothing);
    await t.longPress(find.byKey(const Key('calc-=')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('home-ask')), findsOneWidget);
  });

  testWidgets('with a PIN, quick exit returns only after PIN and =; wrong PIN does not unlock', (t) async {
    final s = await bootSetUp(t);
    await t.runAsync(() => s.setPin('1234'));
    s.quickExit();
    await t.pumpAndSettle();
    await t.longPress(find.byKey(const Key('calc-=')));
    await t.pumpAndSettle();
    expect(find.text('Calculator'), findsOneWidget); // long-press does nothing when a PIN is set
    for (final d in ['9', '9', '9', '9', '=']) {
      await t.tap(find.byKey(Key('calc-$d')));
    }
    await t.pumpAndSettle();
    expect(find.text('Calculator'), findsOneWidget);
    await t.tap(find.byKey(const Key('calc-C')));
    for (final d in ['1', '2', '3', '4', '=']) {
      await t.tap(find.byKey(Key('calc-$d')));
    }
    await t.pumpAndSettle();
    expect(find.byKey(const Key('home-ask')), findsOneWidget);
  });

  testWidgets('returning user with a PIN sees the PIN screen first; backgrounding locks', (t) async {
    final s = await bootSetUp(t);
    await t.runAsync(() => s.setPin('1234'));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pumpAndSettle();
    expect(s.locked, isTrue);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); // user comes back
    await t.pumpAndSettle();
    expect(find.byKey(const Key('home-ask')), findsNothing);
    expect(find.byKey(const Key('pin-1')), findsOneWidget);
    for (final d in ['1', '2', '3', '4']) {
      await t.tap(find.byKey(Key('pin-$d')));
    }
    await t.pump(const Duration(milliseconds: 200));
    await t.pumpAndSettle();
    expect(s.locked, isFalse);
    expect(find.byKey(const Key('home-ask')), findsOneWidget);
  });

  testWidgets('chat text is never written to device storage', (t) async {
    final s = await bootSetUp(t);
    s.msgs.add(Msg({'texts': {'en': 'secret question'}}, from: 'user'));
    expect(await s.store.read('history'), isNull);
    for (final k in ['prefs', 'codes', 'install_id']) {
      expect((await s.store.read(k)) ?? '', isNot(contains('secret question')));
    }
  });
}
