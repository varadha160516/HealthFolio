import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../auth_provider.dart';
import '../../widgets/section_card.dart';

const _categories = [
  'Vitals', 'CBC', 'Diabetes panel', 'Lipid panel', 'Liver function', 'Kidney function', 'Electrolytes',
  'Thyroid panel', 'Vitamins', 'Iron studies', 'Cardiac markers', 'Inflammatory markers', 'Coagulation',
  'Urine routine', 'Hormones', 'Serology', 'Cancer markers', 'Pancreatic function',
];
const _rangeTypes = ['fixed_range', 'open_upper_bound', 'open_lower_bound', 'qualitative', 'none'];

class AdminReviewQueueScreen extends StatefulWidget {
  const AdminReviewQueueScreen({super.key});
  @override
  State<AdminReviewQueueScreen> createState() => _AdminReviewQueueScreenState();
}

class _AdminReviewQueueScreenState extends State<AdminReviewQueueScreen> {
  List<dynamic>? _candidates;
  List<dynamic>? _driftFlags;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadDriftFlags();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final c = await api.getCandidates();
    if (mounted) setState(() => _candidates = c);
  }

  Future<void> _loadDriftFlags() async {
    final api = context.read<AuthProvider>().api;
    final f = await api.getDriftFlags();
    if (mounted) setState(() => _driftFlags = f);
  }

  /// Dictionary curation agent (Roadmap Section 2.9a) — an admin-triggered scan rather than a
  /// truly scheduled one, since this app has no background job scheduler; every parameter is
  /// checked against the model's own clinical knowledge, never a live source (see
  /// server/src/pipeline/dictionaryCuration.ts).
  Future<void> _scanDictionary() async {
    setState(() => _scanning = true);
    try {
      final api = context.read<AuthProvider>().api;
      await api.scanDictionaryDrift();
      await _loadDriftFlags();
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _dismissDriftFlag(String id) async {
    final api = context.read<AuthProvider>().api;
    await api.dismissDriftFlag(id);
    _loadDriftFlags();
  }

  void _openResolveDialog(Map<String, dynamic> candidate) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ResolveSheet(candidate: candidate, onDone: _load),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_candidates == null) return const LoadingCenter();
    return RefreshIndicator(
      onRefresh: () async {
        await _load();
        await _loadDriftFlags();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Dictionary governance queue', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text(
            'Every extracted label with no match at any of the three tiers lands here (Section 5.3) — never silently discarded, '
            'never silently stored under a guessed parameter. Open one to see the dictionary curation agent\'s draft suggestion.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (_candidates!.isEmpty) const SectionCard(child: Text('Nothing pending — the dictionary currently covers everything seen so far.')),
          for (final c in _candidates!)
            SectionCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c['label_as_printed'], style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('value: ${c['value']} ${c['unit'] ?? ''}'),
                      ],
                    ),
                  ),
                  ElevatedButton(onPressed: () => _openResolveDialog(c), child: const Text('Resolve')),
                ],
              ),
            ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Text('Reference-range drift check', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              FilledButton.icon(
                onPressed: _scanning ? null : _scanDictionary,
                icon: _scanning ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.search_rounded, size: 16),
                label: Text(_scanning ? 'Scanning…' : 'Scan now'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'The dictionary curation agent re-checks each canonical parameter\'s stored reference range against the model\'s own '
            'clinical knowledge — not a live published source (Section 3 lists that as a not-yet-built connector) — and flags anything '
            'that looks materially off for you to review. Proposes only; nothing here is applied automatically.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (_driftFlags != null && _driftFlags!.isEmpty) const SectionCard(child: Text('No open flags — run a scan, or everything currently checked looks consistent.')),
          if (_driftFlags != null)
            for (final f in _driftFlags!) _DriftFlagCard(flag: f, onDismiss: () => _dismissDriftFlag(f['id'] as String)),
        ],
      ),
    );
  }
}

class _DriftFlagCard extends StatelessWidget {
  final Map<String, dynamic> flag;
  final VoidCallback onDismiss;
  const _DriftFlagCard({required this.flag, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('${flag['display_name']}', style: const TextStyle(fontWeight: FontWeight.w700))),
              Text('${flag['category']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 6),
          Text('${flag['note']}', style: const TextStyle(fontSize: 13.5, height: 1.4)),
          const SizedBox(height: 6),
          const Text('Based on the model\'s general clinical knowledge, not a live cited source.', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey)),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: onDismiss, child: const Text('Dismiss'))),
        ],
      ),
    );
  }
}

class _ResolveSheet extends StatefulWidget {
  final Map<String, dynamic> candidate;
  final VoidCallback onDone;
  const _ResolveSheet({required this.candidate, required this.onDone});
  @override
  State<_ResolveSheet> createState() => _ResolveSheetState();
}

class _ResolveSheetState extends State<_ResolveSheet> {
  String _mode = 'alias';
  final _aliasTarget = TextEditingController();
  late final _newId = TextEditingController();
  late final _displayName = TextEditingController(text: widget.candidate['label_as_printed']);
  String _category = 'CBC';
  final _unit = TextEditingController(text: 'unitless');
  String _rangeType = 'fixed_range';
  final _low = TextEditingController();
  final _high = TextEditingController();

  Map<String, dynamic>? _draft;
  bool _draftLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDraft();
  }

  /// Dictionary curation agent (Roadmap Section 2.9b) — a draft resolution the admin can accept
  /// as-is, edit, or ignore entirely; it only pre-fills the form fields below, never submits
  /// anything on its own. Fails silently into a blank draft, same as every other nice-to-have
  /// agent summary in this app — a failed draft just means resolving manually, not a broken screen.
  Future<void> _loadDraft() async {
    try {
      final api = context.read<AuthProvider>().api;
      final d = await api.getCandidateDraft(widget.candidate['id'] as String);
      if (!mounted) return;
      setState(() {
        _draft = d;
        if (d['resolution_type'] == 'alias' && d['suggested_canonical_parameter_id'] != null) {
          _mode = 'alias';
          _aliasTarget.text = d['suggested_canonical_parameter_id'] as String;
        } else if (d['resolution_type'] == 'new_param') {
          _mode = 'new_param';
          if (d['suggested_display_name'] != null) _displayName.text = d['suggested_display_name'] as String;
          if (d['suggested_category'] != null && _categories.contains(d['suggested_category'])) _category = d['suggested_category'] as String;
        }
      });
    } catch (_) {
      // silent — see doc comment above
    } finally {
      if (mounted) setState(() => _draftLoading = false);
    }
  }

  Future<void> _submit() async {
    final api = context.read<AuthProvider>().api;
    final id = widget.candidate['id'];
    if (_mode == 'alias') {
      await api.resolveCandidate(id, {'resolution': 'alias', 'canonical_parameter_id': _aliasTarget.text.trim()});
    } else if (_mode == 'new_param') {
      await api.resolveCandidate(id, {
        'resolution': 'new_param',
        'canonical_parameter_id': _newId.text.trim(),
        'display_name': _displayName.text.trim(),
        'category': _category,
        'canonical_unit': _unit.text.trim(),
        'range_type': _rangeType,
        'typical_low': _low.text.trim().isEmpty ? null : num.tryParse(_low.text.trim()),
        'typical_high': _high.text.trim().isEmpty ? null : num.tryParse(_high.text.trim()),
      });
    } else {
      await api.resolveCandidate(id, {
        'resolution': 'interpretive_index',
        'canonical_parameter_id': _newId.text.trim(),
        'display_name': _displayName.text.trim(),
        'category': _category,
      });
    }
    widget.onDone();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        builder: (_, controller) => ListView(
          controller: controller,
          children: [
            if (_draftLoading)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('Drafting a suggestion…', style: TextStyle(fontSize: 13, color: Colors.grey)),
                ]),
              )
            else if (_draft != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.shade100)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.auto_awesome_rounded, size: 15, color: Colors.blueGrey),
                      const SizedBox(width: 6),
                      Text(
                        _draft!['resolution_type'] == 'uncertain' ? 'Agent draft: not confident enough to suggest' : 'Agent draft — pre-filled below, review before saving',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.blueGrey),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text('${_draft!['rationale']}', style: const TextStyle(fontSize: 13, height: 1.35)),
                  ],
                ),
              ),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'alias', label: Text('Alias')),
                ButtonSegment(value: 'new_param', label: Text('New param')),
                ButtonSegment(value: 'interpretive_index', label: Text('Derived index')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 12),
            if (_mode == 'alias') TextField(controller: _aliasTarget, decoration: const InputDecoration(labelText: 'Existing canonical_parameter_id (e.g. "creatinine")')),
            if (_mode != 'alias') ...[
              TextField(controller: _newId, decoration: const InputDecoration(labelText: 'New canonical_parameter_id (snake_case)')),
              const SizedBox(height: 8),
              TextField(controller: _displayName, decoration: const InputDecoration(labelText: 'Display name')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [for (final c in _categories) DropdownMenuItem(value: c, child: Text(c))],
                onChanged: (v) => setState(() => _category = v ?? 'CBC'),
              ),
              if (_mode == 'new_param') ...[
                const SizedBox(height: 8),
                TextField(controller: _unit, decoration: const InputDecoration(labelText: 'Canonical unit')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _rangeType,
                  decoration: const InputDecoration(labelText: 'Range type'),
                  items: [for (final r in _rangeTypes) DropdownMenuItem(value: r, child: Text(r))],
                  onChanged: (v) => setState(() => _rangeType = v ?? 'fixed_range'),
                ),
                const SizedBox(height: 8),
                TextField(controller: _low, decoration: const InputDecoration(labelText: 'Typical low'), keyboardType: TextInputType.number),
                const SizedBox(height: 8),
                TextField(controller: _high, decoration: const InputDecoration(labelText: 'Typical high'), keyboardType: TextInputType.number),
              ] else if (_mode == 'interpretive_index')
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Stored with range_type=interpretive_rule — raw value only, no automated flag until a clinician approves specific threshold logic (Section 4.6).',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
            ],
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _submit, child: const Text('Resolve')),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
