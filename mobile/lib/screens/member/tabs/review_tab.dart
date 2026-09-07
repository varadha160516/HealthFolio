import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../auth_provider.dart';
import '../../../theme.dart';
import '../../../widgets/section_card.dart';

const _tierLabel = {1: 'Tier 1 — exact alias', 2: 'Tier 2 — fuzzy match', 3: 'Tier 3 — semantic guess'};

class ReviewTab extends StatefulWidget {
  final String memberId;
  final VoidCallback onChanged;
  const ReviewTab({super.key, required this.memberId, required this.onChanged});
  @override
  State<ReviewTab> createState() => _ReviewTabState();
}

class _ReviewTabState extends State<ReviewTab> {
  List<dynamic>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final rows = await api.getReviewQueue(widget.memberId);
    if (mounted) setState(() => _items = rows);
  }

  Future<void> _confirm(String id) async {
    await context.read<AuthProvider>().api.confirmParameter(id);
    _load();
    widget.onChanged();
  }

  Future<void> _reject(String id) async {
    await context.read<AuthProvider>().api.rejectParameter(id);
    _load();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (_items == null) return const LoadingCenter();
    if (_items!.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: SectionCard(child: Text('Nothing pending review — everything extracted so far was confident enough to auto-accept.')),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          "These extracted values didn't clear the auto-accept bar (Section 4.5) — either the label match was uncertain, the value "
          "looked implausible, or the parameter isn't in the dictionary yet.",
          style: TextStyle(color: careloopMuted, fontSize: 13),
        ),
        const SizedBox(height: 10),
        for (final row in _items!)
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row['raw_label_as_printed'], style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(row['display_name'] ?? 'no dictionary match — new candidate', style: const TextStyle(color: careloopMuted, fontSize: 12)),
                const SizedBox(height: 4),
                Text('Value: ${row['canonical_value'] ?? row['value_raw']} ${row['unit_raw'] ?? ''}'),
                Text(row['match_tier'] != null ? _tierLabel[row['match_tier']]! : 'No dictionary match', style: const TextStyle(color: careloopMuted, fontSize: 12)),
                const SizedBox(height: 8),
                Row(children: [
                  if (row['canonical_parameter_id'] != null)
                    TextButton(onPressed: () => _confirm(row['id']), child: const Text('Confirm')),
                  TextButton(onPressed: () => _reject(row['id']), style: TextButton.styleFrom(foregroundColor: careloopDanger), child: const Text('Reject')),
                ]),
              ],
            ),
          ),
      ],
    );
  }
}
