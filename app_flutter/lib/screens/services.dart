import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/state.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// Find a service: list (and an area view) from the cached directory, so it works
/// offline. Unverified rows always carry the demo-data tag. Getting a referral code
/// needs a connection.
class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});
  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  String? lga;
  bool mapView = false;
  bool busy = false;

  List<Map<String, dynamic>> _services(AppState s) {
    final all = ((s.bundle?['services'] as List?) ?? []).cast<Map<String, dynamic>>();
    return all.where((x) => (s.tier != '15_17' || x['accepts_under_18'] == true) && (lga == null || x['lga'] == lga)).toList();
  }

  Future<void> _getCode(AppState s, Map<String, dynamic> svc) async {
    setState(() => busy = true);
    try {
      final res = await s.api.post('/v1/referrals', {'service_id': svc['id'], 'lang': s.lang, 'tier': s.tier}) as Map<String, dynamic>;
      final r = SavedReferral(code: res['code'], serviceId: svc['id'], serviceName: svc['name'], area: '${svc['area']}, ${svc['lga']}',
          demo: res['demo'] == true, created: DateTime.now().toIso8601String().substring(0, 10));
      await s.addReferral(r);
      if (mounted) _showCode(s, r);
    } on OfflineException {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('app', 'offline_ask'))));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('app', 'error_generic'))));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _showCode(AppState s, SavedReferral r) {
    final c = NsColors.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('app', 'code_title')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(16)),
              child: SelectableText(r.code, key: const Key('referral-code'),
                  style: TextStyle(fontFamily: kDisplay, fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: 6, color: c.primary)),
            ),
          ),
          const SizedBox(height: 12),
          if (r.demo) const DemoTag(),
          const SizedBox(height: 8),
          Text(s.t('app', 'code_body')),
          const SizedBox(height: 8),
          Text(s.t('app', 'code_saved'), style: Theme.of(ctx).textTheme.bodySmall),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          FilledButton(onPressed: () {
            Navigator.pop(ctx);
            context.pushReplacement('/next');
          }, child: Text(s.t('app', 'tile_next'))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = NsColors.of(context);
    final all = ((s.bundle?['services'] as List?) ?? []).cast<Map<String, dynamic>>();
    final lgas = all.map((e) => e['lga'] as String).toSet().toList()..sort();
    final items = _services(s);
    return NsScaffold(
      title: s.t('app', 'services_title'),
      body: NsPage(children: [
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String?>(
              value: lga,
              decoration: InputDecoration(labelText: s.t('app', 'area'), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              items: [
                DropdownMenuItem(value: null, child: Text(s.t('app', 'all_areas'))),
                for (final l in lgas) DropdownMenuItem(value: l, child: Text(l)),
              ],
              onChanged: (v) => setState(() => lga = v),
            ),
          ),
          const SizedBox(width: 8),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, icon: const Icon(Icons.list), label: Text(s.t('app', 'view_list'))),
              ButtonSegment(value: true, icon: const Icon(Icons.map_outlined), label: Text(s.t('app', 'view_map'))),
            ],
            selected: {mapView},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => mapView = v.first),
          ),
        ]),
        const SizedBox(height: 12),
        if (all.isEmpty) Text(s.t('app', 'offline_ask')),
        if (all.isNotEmpty && items.isEmpty) Text(s.t('app', 'no_services')),
        if (mapView) ..._areaView(context, s, items, lgas) else for (final x in items) _card(context, s, x),
        const SizedBox(height: 8),
        Text('${s.bundle?['demo_mode'] == true ? '' : ''}${s.t('app', 'map_note')}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.text2)),
      ]),
    );
  }

  /// Area view: services grouped by LGA. A pin map needs verified coordinates,
  /// which no demo row has, so none are invented.
  List<Widget> _areaView(BuildContext context, AppState s, List<Map<String, dynamic>> items, List<String> lgas) {
    final c = NsColors.of(context);
    final by = <String, List<Map<String, dynamic>>>{};
    for (final x in items) {
      by.putIfAbsent(x['lga'], () => []).add(x);
    }
    return [
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final l in by.keys)
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() {
              lga = l;
              mapView = false;
            }),
            child: Container(
              width: 150,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.place, color: c.primary),
                Text(l, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${by[l]!.length}', style: TextStyle(fontFamily: kDisplay, fontSize: 28, fontWeight: FontWeight.w700, color: c.primary)),
              ]),
            ),
          ),
      ]),
      const SizedBox(height: 12),
    ];
  }

  Widget _card(BuildContext context, AppState s, Map<String, dynamic> x) {
    final c = NsColors.of(context);
    final demo = x['verified'] != true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: const Color(0xFF0F5C5A),
            padding: const EdgeInsets.all(14),
            child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.end, spacing: 8, runSpacing: 8, children: [
              Text(s.t('referral', 'card_image_label'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              Wrap(spacing: 6, children: [
                if (x['is_free'] == true) Chip2(s.t('referral', 'tag_free'), bg: const Color(0xFFF6C453), fg: const Color(0xFF1B1F23)),
                if (x['youth_friendly'] == true) Chip2(s.t('referral', 'tag_youth'), bg: Colors.white, fg: const Color(0xFF0F5C5A)),
              ]),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (demo) ...[const DemoTag(), const SizedBox(height: 8)] else
                Chip2(s.t('app', 'verified'), bg: c.success, fg: Colors.white),
              Text(x['name'], style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              Text('${x['address']}, ${x['area']} · ${x['lga']}'),
              Text('${x['days']}, ${x['hours']}'),
              const SizedBox(height: 8),
              Text(s.t('referral', 'expect_title'), style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(s.t('referral', 'expect')),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: Key('get-code-${x['id']}'),
                onPressed: busy ? null : () => _getCode(s, x),
                icon: const Icon(Icons.confirmation_number_outlined),
                label: Text(s.t('app', 'get_code')),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
