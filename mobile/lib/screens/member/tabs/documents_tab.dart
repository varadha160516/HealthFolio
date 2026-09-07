import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../auth_provider.dart';
import '../../../theme.dart';
import '../../../utils/motion.dart';
import '../../../widgets/section_card.dart';
import 'document_list_screen.dart';
import 'document_viewer_screen.dart';

/// Documents home: a category grid (counts per type) and a recent-first feed, replacing the old
/// flat grouped-ledger register. Renamed from "Document Library" per the request.
class DocumentsTab extends StatefulWidget {
  final String memberId;
  const DocumentsTab({super.key, required this.memberId});
  @override
  State<DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends State<DocumentsTab> {
  List<dynamic>? _docs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final docs = await api.getDocuments(widget.memberId);
    if (mounted) setState(() => _docs = docs);
  }

  void _openList({String? type, bool autoFocusSearch = false}) {
    Navigator.of(context).push(pushRoute(DocumentListScreen(allDocs: _docs!, documentType: type, autoFocusSearch: autoFocusSearch)));
  }

  @override
  Widget build(BuildContext context) {
    if (_docs == null) return const LoadingCenter();

    final docs = _docs!.cast<Map<String, dynamic>>();
    final counts = <String, int>{for (final t in kDocTypeOrder) t: 0};
    for (final d in docs) {
      final t = d['document_type'] as String?;
      if (t != null && counts.containsKey(t)) counts[t] = counts[t]! + 1;
    }
    final recent = [...docs]..sort((a, b) => (b['upload_date'] as String).compareTo(a['upload_date'] as String));
    final recentTop = recent.take(4).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, careloopFabClearance),
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Documents', style: careloopPageTitle().copyWith(fontSize: 21)),
                  const SizedBox(height: 2),
                  const Text('All your health records in one place', style: TextStyle(color: careloopMuted, fontSize: 11.5)),
                ],
              ),
            ),
            _RoundIconButton(icon: Icons.search_rounded, onTap: () => _openList(autoFocusSearch: true)),
            const SizedBox(width: 8),
            _RoundIconButton(icon: Icons.tune_rounded, onTap: () => _openList()),
          ]),
          const SizedBox(height: 14),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.35,
            children: [
              for (final t in kDocTypeOrder)
                _CategoryTile(
                  label: kDocTypeLabels[t]!,
                  icon: kDocTypeIcons[t]!,
                  bg: kDocTypeColors[t]!.$1,
                  fg: kDocTypeColors[t]!.$2,
                  count: counts[t]!,
                  onTap: () => _openList(type: t),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(child: Text('Recent Documents', style: careloopSectionHeading().copyWith(fontSize: 15))),
                  InkWell(onTap: () => _openList(), child: const Text('View all', style: TextStyle(color: careloopAccent, fontWeight: FontWeight.w600, fontSize: 11.5))),
                ]),
                const SizedBox(height: 8),
                if (recentTop.isEmpty)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Nothing filed yet — tap Add Document to start.', style: TextStyle(color: careloopMuted, fontSize: 12.5)))
                else
                  for (final d in recentTop) _RecentRow(doc: d),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIconButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: careloopSurface, shape: BoxShape.circle, border: careloopCardBorder),
        child: Icon(icon, size: 16, color: careloopTextPrimary),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;
  final int count;
  final VoidCallback onTap;
  const _CategoryTile({required this.label, required this.icon, required this.bg, required this.fg, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(careloopRadiusLg),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [bg, careloopSurface]), borderRadius: BorderRadius.circular(careloopRadiusLg)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 30, height: 30, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: Icon(icon, size: 14, color: fg)),
            const Spacer(),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11.5, color: careloopTextPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text('$count', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20, color: fg)),
            const Text('Records', style: TextStyle(fontSize: 9.5, color: careloopMuted)),
          ],
        ),
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  final Map<String, dynamic> doc;
  const _RecentRow({required this.doc});
  @override
  Widget build(BuildContext context) {
    final type = doc['document_type'] as String? ?? 'other';
    final (bg, fg) = kDocTypeColors[type] ?? (careloopSurfaceRaised, careloopMuted);
    final icon = kDocTypeIcons[type] ?? Icons.insert_drive_file_rounded;
    final label = kDocTypeLabels[type] ?? 'Other';
    final source = doc['source_lab_name']?.toString() ?? 'Unlabeled source';
    final date = ((doc['test_date'] ?? doc['upload_date']) as String).substring(0, 10);
    return InkWell(
      onTap: () => Navigator.of(context).push(pushRoute(DocumentViewerScreen(documentId: doc['id'] as String))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Container(width: 32, height: 32, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11)), child: Icon(icon, size: 15, color: fg)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(source, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(date, style: const TextStyle(color: careloopMuted, fontSize: 10.5)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
            child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ]),
      ),
    );
  }
}
