import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/state.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'staff/staff.dart';

/// Session kits: lesson outline, quiz and myth-busting cards built only from the
/// knowledge base. Cached in the content bundle, so they work offline.
class KitsScreen extends StatefulWidget {
  const KitsScreen({super.key});
  @override
  State<KitsScreen> createState() => _KitsScreenState();
}

class _KitsScreenState extends State<KitsScreen> {
  String lang = 'en';
  final Map<int, bool> revealed = {};

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = NsColors.of(context);
    final tt = Theme.of(context).textTheme;
    final kit = ((s.bundle?['kits'] as Map?)?[lang] as Map?)?.cast<String, dynamic>();
    if (kit == null) {
      return Scaffold(appBar: staffBar(context, 'Session kits'), body: const Center(child: Text('Kits load with the content bundle. Connect once to download.')));
    }
    final lesson = (kit['lesson'] as Map).cast<String, dynamic>();
    final quiz = (kit['quiz'] as List).cast<Map<String, dynamic>>();
    final myths = (kit['myths'] as List).cast<Map<String, dynamic>>();
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Session kits'),
          actions: [
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'en', label: Text('EN')), ButtonSegment(value: 'pcm', label: Text('Pidgin'))],
              selected: {lang},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => lang = v.first),
            ),
            const SizedBox(width: 8),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Lesson'), Tab(text: 'Quiz'), Tab(text: 'Myth cards')]),
        ),
        body: TabBarView(children: [
          NsPage(maxWidth: 760, children: [
            Text(lesson['title'], style: tt.headlineSmall),
            Text('About ${lesson['duration_min']} minutes', style: tt.bodySmall),
            const SizedBox(height: 12),
            for (final (i, o) in (lesson['outline'] as List).indexed) Text('${i + 1}. $o'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFF6C453), borderRadius: BorderRadius.circular(12)),
              child: Text(lesson['curriculum_alignment'], style: const TextStyle(color: Color(0xFF1B1F23))),
            ),
            const SizedBox(height: 16),
            for (final sec in (lesson['sections'] as List).cast<Map<String, dynamic>>())
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(sec['title'], style: tt.titleMedium?.copyWith(color: c.primary)),
                      const SizedBox(height: 6),
                      Text(sec['text']),
                      SourcesLine(sources: [sec]),
                      Text(sec['review_status'], style: tt.bodySmall),
                    ]),
                  ),
                ),
              ),
            if ((lesson['missing_topics_todo'] as List).isNotEmpty)
              Text('TODO – topics waiting for content from the guideline PDFs: ${(lesson['missing_topics_todo'] as List).join(', ')}', style: tt.bodySmall),
          ]),
          NsPage(maxWidth: 760, children: [
            if (quiz.isEmpty) const Text('No quiz items yet. Add `quiz:` entries to knowledge-base chunks.'),
            for (final (i, q) in quiz.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${i + 1}. True or false?', style: tt.labelLarge?.copyWith(color: c.primary)),
                      Text(q['statement'], style: tt.titleMedium),
                      const SizedBox(height: 8),
                      if (revealed[i] == true) ...[
                        Text(q['answer'] == true ? 'TRUE' : 'FALSE', style: TextStyle(fontWeight: FontWeight.w800, color: c.primary, fontSize: 18)),
                        if ((q['explanation'] as String).isNotEmpty) Text(q['explanation']),
                        Text('${q['review_status']} · ${q['source_document']}', style: tt.bodySmall),
                      ] else
                        OutlinedButton(onPressed: () => setState(() => revealed[i] = true), child: const Text('Show answer')),
                    ]),
                  ),
                ),
              ),
          ]),
          NsPage(maxWidth: 760, children: [
            if (myths.isEmpty) const Text('No myth cards yet. Add `myths:` entries to knowledge-base chunks.'),
            for (final m in myths)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('MYTH', style: TextStyle(fontWeight: FontWeight.w800, color: c.accent)),
                      Text(m['myth'], style: tt.titleMedium),
                      const Divider(),
                      Text('FACT', style: TextStyle(fontWeight: FontWeight.w800, color: c.success)),
                      Text(m['fact'], style: tt.bodyLarge),
                      const SizedBox(height: 6),
                      Text('${m['review_status']} · ${m['source_document']}', style: tt.bodySmall),
                    ]),
                  ),
                ),
              ),
          ]),
        ]),
      ),
    );
  }
}
