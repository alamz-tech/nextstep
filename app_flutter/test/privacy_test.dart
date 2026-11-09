// Red-team app_cases (tests/redteam.yaml): quick exit, PIN lock, history, under-15.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextstep/core/state.dart';
import 'package:nextstep/main.dart';
import 'package:provider/provider.dart';

Future<AppState> makeState({bool onboarded = true, String? pin}) async {
  FlutterSecureStorage.setMockInitialValues({});
  final s = AppState();
  await s.init();
  if (onboarded) {
    s.onboarded = true;
    s.tier = '18_24';
  }
  if (pin != null) await s.setPin(pin);
  s.locked = false;
  return s;
}

Future<void> pump(WidgetTester t, AppState s) async {
  await t.pumpWidget(ChangeNotifierProvider.value(value: s, child: const NextStepApp()));
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // No network in tests: every HTTP call fails fast and the app falls back to cached/asset content.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('nextstep/privacy'), (_) async => null);
  });

  testWidgets('quick exit shows a neutral calculator with no NextStep text', (t) async {
    final s = await makeState();
    await pump(t, s);
    expect(find.text('NextStep'), findsWidgets);
    await t.tap(find.byKey(const Key('quick-exit')));
    await t.pumpAndSettle();
    expect(find.text('Calculator'), findsOneWidget);
    expect(find.textContaining('NextStep'), findsNothing);
    expect(find.textContaining('HIV'), findsNothing);
  });

  testWidgets('quick exit is present on every learner screen', (t) async {
    final s = await makeState();
    await pump(t, s);
    for (final tile in ['tile-ask', 'tile-check', 'tile-find', 'tile-next']) {
      await t.tap(find.byKey(Key(tile)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('quick-exit')), findsOneWidget, reason: tile);
      await t.pageBack();
      await t.pumpAndSettle();
    }
  });

  testWidgets('after quick exit, the app stays locked until the PIN is typed and = pressed', (t) async {
    final s = await makeState(pin: '1234');
    await pump(t, s);
    await t.tap(find.byKey(const Key('quick-exit')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('calc-=')));
    await t.pumpAndSettle();
    expect(find.text('Calculator'), findsOneWidget);
    for (final d in ['1', '2', '3', '4']) {
      await t.tap(find.byKey(Key('calc-$d')));
    }
    await t.tap(find.byKey(const Key('calc-=')));
    await t.pumpAndSettle();
    expect(find.text('Calculator'), findsNothing);
    expect(find.byKey(const Key('tile-ask')), findsOneWidget);
  });

  testWidgets('wrong PIN does not unlock', (t) async {
    final s = await makeState(pin: '1234');
    s.locked = true;
    await pump(t, s);
    for (final d in ['9', '9', '9', '9']) {
      await t.tap(find.byKey(Key('pin-$d')));
    }
    await t.pumpAndSettle();
    expect(s.locked, isTrue);
    expect(find.byKey(const Key('tile-ask')), findsNothing);
  });

  testWidgets('going to background locks the app when a PIN is set', (t) async {
    final s = await makeState(pin: '1234');
    await pump(t, s);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pumpAndSettle();
    expect(s.locked, isTrue);
  });

  testWidgets('chat history is not kept by default', (t) async {
    final s = await makeState();
    expect(s.keepHistory, isFalse);
    await s.addHistory({'from': 'user', 'text': 'secret question'});
    final stored = await s.store.read('history');
    expect(stored, isNull);
  });

  testWidgets('under-15 exit saves nothing', (t) async {
    final s = await makeState(onboarded: false);
    await pump(t, s);
    await t.tap(find.byKey(const Key('consent-agree')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('age-under_15')));
    await t.pumpAndSettle();
    expect(s.onboarded, isFalse);
    expect(await s.store.readJson('prefs'), isNull);
  });
}
