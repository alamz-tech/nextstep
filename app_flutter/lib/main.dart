import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/notifications.dart';
import 'core/privacy.dart';
import 'core/state.dart';
import 'screens/chat.dart';
import 'screens/join.dart';
import 'screens/lock.dart';
import 'screens/staff/staff.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ScreenPrivacy.setSecure(true); // Android: hide content in recent apps
  final state = AppState();
  await state.init();
  Notifications.init();
  runApp(ChangeNotifierProvider.value(value: state, child: const NextStepApp()));
}

class NextStepApp extends StatefulWidget {
  const NextStepApp({super.key});
  @override
  State<NextStepApp> createState() => _NextStepAppState();
}

class _NextStepAppState extends State<NextStepApp> {
  late final GoRouter router;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    router = GoRouter(
      redirect: (_, st) {
        final p = st.uri.path;
        if (p.startsWith('/staff/') && s.staff?.role != 'facilitator') return '/staff';
        if (p == '/clinic' && s.staff?.role != 'clinic_partner') return '/staff';
        return null;
      },
      routes: [
        GoRoute(path: '/', builder: (_, __) => const ChatScreen()),
        GoRoute(path: '/join/:code', builder: (_, st) => JoinScreen(code: st.pathParameters['code']!)),
        GoRoute(path: '/staff', builder: (_, __) => const StaffLoginScreen()),
        GoRoute(path: '/staff/sessions', builder: (_, __) => const SessionsScreen()),
        GoRoute(path: '/staff/session/:id', builder: (_, st) => SessionScreen(id: st.pathParameters['id']!)),
        GoRoute(path: '/staff/projector/:id', builder: (_, st) => ProjectorScreen(id: st.pathParameters['id']!)),
        GoRoute(path: '/clinic', builder: (_, __) => const ClinicScreen()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return MaterialApp.router(
      title: 'NextStep',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF0F5C5A), fontFamily: 'Atkinson'),
      routerConfig: router,
      builder: (ctx, child) {
        if (!s.ready) return const Scaffold(backgroundColor: Color(0xFFEAE6DF));
        if (s.disguised) return const NeutralScreen();
        return child!;
      },
    );
  }
}
