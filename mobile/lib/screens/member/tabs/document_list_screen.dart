import 'package:flutter/material.dart';
import '../../../theme.dart';
import '../../../utils/motion.dart';
import '../../../widgets/empty_state.dart';
import 'document_viewer_screen.dart';

const kDocTypeLabels = <String, String>{
  'lab_report': 'Lab Reports',
  'prescription': 'Prescriptions',
  'radiology_scan': 'Radiology Reports',
  'discharge_summary': 'Discharge Summaries',
  'vaccination_record': 'Immunizations',
  'insurance_policy': 'Insurance',
  'other': 'Other',
};
const kDocTypeOrder = ['lab_report', 'prescription', 'radiology_scan', 'discharge_summary', 'vaccination_record', 'insurance_policy', 'other'];
const kDocTypeColors = <String, (Color, Color)>{
  'lab_report': (careloopLavender, careloopSuccess),
  'prescription': (careloopOrangeBg, careloopOrange),
  'radiology_scan': (careloopPeriwinkle, careloopInfo),
  'discharge_summary': (careloopGreenBg, careloopGreen),
  'vaccination_record': (careloopAccentLight, careloopAccent),
  'insurance_policy': (careloopTealBg, careloopTeal),
  'other': (careloopSurfaceRaised, careloopMuted),
};
const kDocTypeIcons = <String, IconData>{
  'lab_report': Icons.science_rounded,
  'prescription': Icons.medication_rounded,
  'radiology_scan': Icons.camera_alt_rounded,
  'discharge_summary': Icons.assignment_turned_in_rounded,
  'vaccination_record': Icons.vaccines_rounded,
  'insurance_policy': Icons.shield_rounded,
  'other': Icons.insert_drive_file_rounded,
};

enum _SortBy { recent, oldest, name }

enum _StatusFilter { all, parsed, needsReview, manualEntry }

/// One screen, two jobs: a single document type (tapped from a Documents-tab tile) or every
/// document across all types ("View all" / the header's search+filter icons) — same list, same
/// sort/filter/search chrome either way, just with or without the type restriction and its stat
/// chips.
class DocumentListScreen extends StatefulWidget {
  final List<dynamic> allDocs;
  final String? documentType; // null = every type ("All Documents")
  final bool autoFocusSearch;
  const DocumentListScreen({super.key, required this.allDocs, this.documentType, this.autoFocusSearch = false});

  @override
  State<DocumentListScreen> createState() => _DocumentListScreenState();
}

class _DocumentListScreenState extends State<DocumentListScreen> {
  _SortBy _sort = _SortBy.recent;
  _StatusFilter _statusFilter = _StatusFilter.all;
  bool _searching = false;
  bool _gridView = false;
  final _searchController = TextEditingController();
  late final FocusNode _searchFocus;

  @override
  void initState() {
    super.initState();
    _searchFocus = FocusNode();
    if (widget.autoFocusSearch) {
      _searching = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _scoped {
    var docs = widget.allDocs.cast<Map<String, dynamic>>();
    if (widget.documentType != null) docs = docs.where((d) => d['document_type'] == widget.documentType).toList();
    return docs;
  }

  List<Map<String, dynamic>> get _filtered {
    var docs = _scoped;
    switch (_statusFilter) {
      case _StatusFilter.parsed:
        docs = docs.where((d) => d['status'] == 'parsed').toList();
      case _StatusFilter.needsReview:
        docs = docs.where((d) => d['status'] == 'pending_review').toList();
      case _StatusFilter.manualEntry:
        docs = docs.where((d) => d['status'] == 'manual_entry_required').toList();
      case _StatusFilter.all:
        break;
    }
    final q = _searchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      docs = docs.where((d) {
        final source = (d['source_lab_name'] as String? ?? '').toLowerCase();
        final type = kDocTypeLabels[d['document_type']]?.toLowerCase() ?? '';
        return source.contains(q) || type.contains(q);
      }).toList();
    }
    docs = [...docs];
    switch (_sort) {
      case _SortBy.recent:
        docs.sort((a, b) => (b['upload_date'] as String).compareTo(a['upload_date'] as String));
      case _SortBy.oldest:
        docs.sort((a, b) => (a['upload_date'] as String).compareTo(b['upload_date'] as String));
      case _SortBy.name:
        docs.sort((a, b) => (a['source_lab_name'] as String? ?? '').toLowerCase().compareTo((b['source_lab_name'] as String? ?? '').toLowerCase()));
    }
    return docs;
  }

  String get _title => widget.documentType != null ? kDocTypeLabels[widget.documentType]! : 'All Documents';

  @override
  Widget build(BuildContext context) {
    final scoped = _scoped;
    final filtered = _filtered;
    final parsedCount = scoped.where((d) => d['status'] == 'parsed').length;
    final reviewCount = scoped.where((d) => d['status'] == 'pending_review').length;
    final manualCount = scoped.where((d) => d['status'] == 'manual_entry_required').length;

    return Scaffold(
      backgroundColor: careloopBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: careloopSurface, shape: BoxShape.circle, border: careloopCardBorder),
                    child: const Icon(Icons.arrow_back_ios_new_rounded, size: 15, color: careloopTextPrimary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_title, style: careloopSectionHeading().copyWith(fontSize: 17)),
                      Text('${scoped.length} record${scoped.length == 1 ? '' : 's'}', style: const TextStyle(color: careloopMuted, fontSize: 11)),
                    ],
                  ),
                ),
                _RoundIconButton(
                  icon: _searching ? Icons.close_rounded : Icons.search_rounded,
                  onTap: () => setState(() {
                    _searching = !_searching;
                    if (!_searching) _searchController.clear();
                  }),
                ),
                const SizedBox(width: 8),
                _RoundIconButton(icon: Icons.tune_rounded, onTap: _openFilterSheet),
              ]),
              if (_searching) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(hintText: 'Search by source or type', prefixIcon: Icon(Icons.search_rounded, size: 18)),
                ),
              ],
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _StatChip(label: 'Parsed', count: parsedCount, bg: careloopSuccessBg, fg: careloopSuccess)),
                const SizedBox(width: 8),
                Expanded(child: _StatChip(label: 'Needs review', count: reviewCount, bg: careloopWarningBg, fg: careloopWarning)),
                const SizedBox(width: 8),
                Expanded(child: _StatChip(label: 'Manual entry', count: manualCount, bg: careloopAbnormalBg, fg: careloopDanger)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: PopupMenuButton<_SortBy>(
                    initialValue: _sort,
                    onSelected: (v) => setState(() => _sort = v),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: _SortBy.recent, child: Text('Recently added')),
                      PopupMenuItem(value: _SortBy.oldest, child: Text('Oldest first')),
                      PopupMenuItem(value: _SortBy.name, child: Text('Name A-Z')),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(999), border: careloopCardBorder),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Text('Sort by: ', style: TextStyle(color: careloopMuted, fontSize: 11.5, fontWeight: FontWeight.w500)),
                        Text(switch (_sort) { _SortBy.recent => 'Recently added', _SortBy.oldest => 'Oldest first', _SortBy.name => 'Name A-Z' },
                            style: const TextStyle(color: careloopTextPrimary, fontSize: 11.5, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 4),
                        const Icon(Icons.expand_more_rounded, size: 16, color: careloopTextPrimary),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(999), border: careloopCardBorder),
                  child: Row(children: [
                    _ViewToggleButton(icon: Icons.view_list_rounded, selected: !_gridView, onTap: () => setState(() => _gridView = false)),
                    _ViewToggleButton(icon: Icons.grid_view_rounded, selected: _gridView, onTap: () => setState(() => _gridView = true)),
                  ]),
                ),
              ]),
              const SizedBox(height: 10),
              Expanded(
                child: filtered.isEmpty
                    ? const EmptyState(icon: Icons.folder_open_rounded, message: 'No documents to display')
                    : _gridView
                        ? GridView.builder(
                            padding: const EdgeInsets.only(top: 4),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.95),
                            itemCount: filtered.length,
                            itemBuilder: (_, i) => _DocGridCard(doc: filtered[i]),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(top: 4),
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (_, i) => _DocRow(doc: filtered[i]),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 4), child: Align(alignment: Alignment.centerLeft, child: Text('Filter by status', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)))),
          for (final f in _StatusFilter.values)
            RadioListTile<_StatusFilter>(
              value: f,
              groupValue: _statusFilter,
              title: Text(switch (f) {
                _StatusFilter.all => 'All statuses',
                _StatusFilter.parsed => 'Parsed',
                _StatusFilter.needsReview => 'Needs review',
                _StatusFilter.manualEntry => 'Manual entry',
              }),
              onChanged: (v) {
                setState(() => _statusFilter = v!);
                Navigator.of(context).pop();
              },
            ),
        ]),
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

class _ViewToggleButton extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ViewToggleButton({required this.icon, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(color: selected ? careloopAccentLight : Colors.transparent, shape: BoxShape.circle),
        child: Icon(icon, size: 14, color: selected ? careloopAccent : careloopMutedDim),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color bg;
  final Color fg;
  const _StatChip({required this.label, required this.count, required this.bg, required this.fg});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Text('$count', style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 17)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w500, fontSize: 9.5), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

(String, StatusPill) _statusInfo(Map<String, dynamic> doc) {
  final status = doc['status'] as String?;
  return switch (status) {
    'parsed' => ('Parsed', const StatusPill('Parsed', tone: PillTone.success)),
    'manual_entry_required' => ('Manual entry', const StatusPill('Manual entry', tone: PillTone.danger)),
    _ => ('Needs review', const StatusPill('Needs review', tone: PillTone.warning)),
  };
}

class _DocRow extends StatelessWidget {
  final Map<String, dynamic> doc;
  const _DocRow({required this.doc});
  @override
  Widget build(BuildContext context) {
    final type = doc['document_type'] as String? ?? 'other';
    final (bg, fg) = kDocTypeColors[type] ?? (careloopSurfaceRaised, careloopMuted);
    final icon = kDocTypeIcons[type] ?? Icons.insert_drive_file_rounded;
    final source = doc['source_lab_name']?.toString() ?? 'Unlabeled source';
    final date = ((doc['test_date'] ?? doc['upload_date']) as String).substring(0, 10);
    final (_, pill) = _statusInfo(doc);
    return InkWell(
      borderRadius: BorderRadius.circular(careloopRadiusMd),
      onTap: () => Navigator.of(context).push(pushRoute(DocumentViewerScreen(documentId: doc['id'] as String))),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder, boxShadow: careloopCardShadow),
        child: Row(children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 16, color: fg)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(source, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(date, style: const TextStyle(color: careloopMuted, fontSize: 10.5)),
              ],
            ),
          ),
          pill,
        ]),
      ),
    );
  }
}

class _DocGridCard extends StatelessWidget {
  final Map<String, dynamic> doc;
  const _DocGridCard({required this.doc});
  @override
  Widget build(BuildContext context) {
    final type = doc['document_type'] as String? ?? 'other';
    final (bg, fg) = kDocTypeColors[type] ?? (careloopSurfaceRaised, careloopMuted);
    final icon = kDocTypeIcons[type] ?? Icons.insert_drive_file_rounded;
    final source = doc['source_lab_name']?.toString() ?? 'Unlabeled source';
    final date = ((doc['test_date'] ?? doc['upload_date']) as String).substring(0, 10);
    final (_, pill) = _statusInfo(doc);
    return InkWell(
      borderRadius: BorderRadius.circular(careloopRadiusMd),
      onTap: () => Navigator.of(context).push(pushRoute(DocumentViewerScreen(documentId: doc['id'] as String))),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder, boxShadow: careloopCardShadow),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 34, height: 34, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 16, color: fg)),
            const Spacer(),
            Text(source, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(date, style: const TextStyle(color: careloopMuted, fontSize: 10)),
            const SizedBox(height: 6),
            pill,
          ],
        ),
      ),
    );
  }
}
