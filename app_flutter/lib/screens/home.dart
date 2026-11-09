import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/state.dart';
import '../widgets/common.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return NsScaffold(
      title: 'NextStep',
      showLogo: true,
      actions: [
        IconButton(tooltip: s.t('app', 'settings_title'), onPressed: () => context.push('/settings'), icon: const Icon(Icons.settings_outlined)),
      ],
      body: NsPage(children: [
        Text(s.t('app', 'home_title'), style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        BigTile(tileKey: const Key('tile-ask'), icon: Icons.chat_bubble_outline, title: s.t('menu', 'row_ask'), subtitle: s.t('menu', 'row_ask_desc'),
            onTap: () => context.push('/ask')),
        const SizedBox(height: 12),
        BigTile(tileKey: const Key('tile-check'), icon: Icons.verified_user_outlined, title: s.t('menu', 'row_check'), subtitle: s.t('menu', 'row_check_desc'),
            onTap: () => context.push('/check')),
        const SizedBox(height: 12),
        BigTile(tileKey: const Key('tile-find'), icon: Icons.place_outlined, title: s.t('menu', 'row_find'), subtitle: s.t('menu', 'row_find_desc'),
            onTap: () => context.push('/services')),
        const SizedBox(height: 12),
        BigTile(tileKey: const Key('tile-next'), icon: Icons.event_note_outlined, title: s.t('app', 'tile_next'), subtitle: s.t('app', 'tile_next_desc'),
            onTap: () => context.push('/next')),
        const SizedBox(height: 24),
        if (s.bundle?['demo_mode'] == true)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF6C453), borderRadius: BorderRadius.circular(12)),
            child: Text(s.t('sim', 'banner'), style: const TextStyle(color: Color(0xFF1B1F23), fontWeight: FontWeight.w700)),
          ),
      ]),
    );
  }
}
