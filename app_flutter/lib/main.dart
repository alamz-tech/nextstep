import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/notifications.dart';
import 'core/privacy.dart';
import 'core/state.dart';
import 'core/theme.dart';
import 'screens/ask.dart';
import 'screens/check.dart';
import 'screens/crisis.dart';
import 'screens/home.dart';
import 'screens/join.dart';
import 'screens/kits.dart';
import 'screens/lock.dart';
import 'screens/next_steps.dart';
import 'screens/onboarding.dart';
import 'screens/services.dart';
import 'screens/settings.dart';
import 'screens/staff/staff.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ScreenPrivacy.setSecure(true); // hide content in recent apps / block screenshots (Android)
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
    const learnerRoutes = {'/ask', '/check', '/services', '/next', '/settings'};
    router = GoRouter(
      refreshListenable: s,
      redirect: (ctx, st) {
        final p = st.uri.path;
        if (learnerRoutes.contains(p) && !s.onboarded) return '/';
        if (p.startsWith('/staff/') && s.staff == null) return '/staff';
        if (p == '/clinic' && s.staff?.role != 'clinic_partner') return '/staff';
        return null;
      },
      routes: [
        GoRoute(path: '/', builder: (_, __) => s.onboarded ? const HomeScreen() : const OnboardingScreen()),
        GoRoute(path: '/ask', builder: (_, __) => const AskScreen()),
        GoRoute(path: '/check', builder: (_, __) => const CheckScreen()),
        GoRoute(path: '/services', builder: (_, __) => const ServicesScreen()),
        GoRoute(path: '/next', builder: (_, __) => const NextStepsScreen()),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
        GoRoute(path: '/crisis', builder: (_, __) => CrisisScreen(payload: s.pendingCrisis ?? {'refs': [['crisis', 'violence']]})),
        GoRoute(path: '/join/:code', builder: (_, st) => JoinScreen(code: st.pathParameters['code']!)),
        GoRoute(path: '/staff', builder: (_, __) => const StaffLoginScreen()),
        GoRoute(path: '/staff/sessions', builder: (_, __) => const SessionsScreen()),
        GoRoute(path: '/staff/session/:id', builder: (_, st) => SessionScreen(id: st.pathParameters['id']!)),
        GoRoute(path: '/staff/projector/:id', builder: (_, st) => ProjectorScreen(id: st.pathParameters['id']!)),
        GoRoute(path: '/staff/kits', builder: (_, __) => const KitsScreen()),
        GoRoute(path: '/staff/admin', builder: (_, __) => const AdminScreen()),
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
    // Lock when the app goes to the background (if the learner set a PIN).
    if (st == AppLifecycleState.paused || st == AppLifecycleState.hidden) context.read<AppState>().lockIfPin();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return MaterialApp.router(
      title: 'NextStep', // neutral name: shown in the app switcher and browser tab
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      routerConfig: router,
      builder: (ctx, child) {
        if (!s.ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (s.disguised) return const NeutralScreen();
        if (s.locked) return const LockScreen();
        return child!;
      },
    );
  }
}
