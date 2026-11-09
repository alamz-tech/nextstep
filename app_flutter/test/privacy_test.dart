// Red-team app_cases (tests/redteam.yaml): quick exit and on-device storage.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextstep/core/state.dart';
import 'package:nextstep/main.dart';
import 'package:provider/provider.dart';

Future<AppState> boot(WidgetTester t) async {
  FlutterSecureStorage.setMockInitialValues({});
  final s = AppState();
  await t.runAsync(s.init);
  await t.pumpWidget(ChangeNotifierProvider.value(value: s, child: const NextStepApp()));
  await t.pump(const Duration(milliseconds: 100));
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('nextstep/privacy'), (_) async => null));

  testWidgets('quick exit shows a neutral calculator with no NextStep text', (t) async {
    await boot(t);
    expect(find.text('NextStep'), findsOneWidget);
    await t.tap(find.byKey(const Key('chat-menu')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('quick-exit')));
    await t.pumpAndSettle();
    expect(find.text('Calculator'), findsOneWidget);
    expect(find.textContaining('NextStep'), findsNothing);
    expect(find.textContaining('HIV'), findsNothing);
  });

  testWidgets('quick exit clears the chat and returns only on long-press =', (t) async {
    final s = await boot(t);
    s.msgs.add(Msg({'texts': {'en': 'secret question'}}, from: 'user'));
    s.quickExit();
    await t.pumpAndSettle();
    expect(s.msgs, isEmpty);
    await t.tap(find.byKey(const Key('calc-=')));
    await t.pumpAndSettle();
    expect(find.text('Calculator'), findsOneWidget);
    await t.longPress(find.byKey(const Key('calc-=')));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Calculator'), findsNothing);
  });

  testWidgets('chat text is never written to device storage', (t) async {
    final s = await boot(t);
    s.msgs.add(Msg({'texts': {'en': 'secret question'}}, from: 'user'));
    expect(await s.store.read('history'), isNull);
    expect(await s.store.read('install_id'), isNotNull);
  });
}
