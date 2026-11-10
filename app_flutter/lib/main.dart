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
import 'ui/learner.dart';

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

class _NextStepAppState extends State<NextStepApp> with WidgetsBindingObserver {
  late final GoRouter router;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final s = context.read<AppState>();
    const learner = ['/ask', '/check', '/services', '/service', '/code', '/settings', '/crisis'];
    router = GoRouter(
      refreshListenable: s,
      redirect: (_, st) {
        final p = st.uri.path;
        // Learner screens need first-time setup; Home ("/") shows setup itself when needed.
        if (learner.any((r) => p == r || p.startsWith('$r/')) && !s.setupDone) return '/';
        if (p.startsWith('/staff/') && s.staff?.role != 'facilitator') return '/staff';
        if (p == '/clinic' && s.staff?.role != 'clinic_partner') return '/staff';
        return null;
      },
      routes: [
        GoRoute(path: '/', builder: (_, __) => const RootScreen()),
        GoRoute(path: '/ask', builder: (_, __) => const ChatScreen()),
        GoRoute(path: '/check', builder: (_, __) => const CheckScreen()),
        GoRoute(path: '/services', builder: (_, __) => const ServicesScreen()),
        GoRoute(path: '/service', builder: (_, st) => ServiceScreen(svc: st.extra as Map<String, dynamic>? ?? const {}),
            redirect: (_, st) => st.extra == null ? '/services' : null),
        GoRoute(path: '/code/:code', builder: (_, st) => CodeScreen(code: st.pathParameters['code']!)),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
        GoRoute(path: '/crisis', builder: (_, __) => const CrisisScreen()),
        // Students (QR code) and staff never pass through the learner Home.
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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState st) {
    // Lock when the app goes to the background, if the learner set a PIN.
    if (st == AppLifecycleState.paused || st == AppLifecycleState.hidden) context.read<AppState>().lockIfPin();
  }

  bool _isLearnerPath() {
    final p = router.routeInformationProvider.value.uri.path;
    return !(p.startsWith('/join') || p.startsWith('/staff') || p.startsWith('/clinic'));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return MaterialApp.router(
      title: 'NextStep',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFFA3305A), fontFamily: 'Atkinson'),
      routerConfig: router,
      builder: (ctx, child) {
        if (!s.ready) return const Scaffold(backgroundColor: Color(0xFFEAE6DF));
        if (s.disguised) return const NeutralScreen();
        if (s.locked && _isLearnerPath()) return const PinScreen();
        return child!;
      },
    );
  }
}
