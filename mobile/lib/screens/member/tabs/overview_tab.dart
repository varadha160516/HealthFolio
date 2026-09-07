import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../auth_provider.dart';
import '../../../theme.dart';
import '../../../utils/range_format.dart';
import '../../../widgets/ledger.dart';
import '../../../widgets/section_card.dart';

/// Section 3.2 #4 — the one screen a member can show a new doctor in ten seconds. Design system
/// Section 3.4/4: the stat header plus a ledger of everything currently flagged, styled as the
/// system's acceptance-reference screen.
class OverviewTab extends StatefulWidget {
  final String memberId;
  const OverviewTab({super.key, required this.memberId});
  @override
  State<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<OverviewTab> {
  Map<String, dynamic>? _summary;
  String? _insight;
  bool _insightLoading = false;

  // Tap targets for the stat banner — "Needs attention"/"Newly added"/"Tracked" scroll straight to
  // their section instead of just being a static count.
  final _needsAttentionKey = GlobalKey();
  final _newlyAddedKey = GlobalKey();
  final _allResultsKey = GlobalKey();

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeInOut, alignment: 0.05);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final s = await api.getSummary(widget.memberId);
    if (mounted) setState(() => _summary = s);
    _loadInsight();
  }

  /// Fetched separately from the summary and never blocks the main screen on it — the health
  /// insights agent call can take a couple of seconds (it's a model call), and the rest of
  /// Overview is real data the member shouldn't have to wait on. Fails silently: this is a
  /// nice-to-have summary, not core data, so a failed call just means the card doesn't appear.
  Future<void> _loadInsight() async {
    final api = context.read<AuthProvider>().api;
    setState(() => _insightLoading = true);
    try {
      final r = await api.getHealthInsights(widget.memberId);
      if (mounted) setState(() => _insight = r['summary'] as String?);
    } catch (_) {
      // silent — see doc comment above
    } finally {
      if (mounted) setState(() => _insightLoading = false);
    }
  }

  LedgerRow _paramRow(Map<String, dynamic> p) {
    final value = p['canonical_value'];
    final unit = p['canonical_unit'] as String?;
    final displayValue = value != null ? '$value' : (p['value_raw']?.toString() ?? '—');
    final flag = p['in_range_flag'] as String?;
    return LedgerRow(
      label: p['display_name'] ?? '',
      sublabel: '${p['category'] ?? ''} · ${p['test_date'] ?? ''}',
      labelSize: careloopTypeBody - 1,
      sublabelSize: careloopTypeCaption - 0.5,
      trailing: flag == 'out_of_range' || flag == 'in_range'
          ? LedgerValueFlag(
              value: displayValue,
              unit: unit,
              flagLabel: flagWord(flag!, p['range_type'] as String?, value as num?, p['resolved_reference_range'] as Map<String, dynamic>?),
              outOfRange: flag == 'out_of_range',
            )
          : LedgerValue(displayValue, unit: unit),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_summary == null) return const LoadingCenter();
    final meds = _summary!['currentMedications'] as List<dynamic>;
    final parameters = _summary!['parameters'] as Map<String, dynamic>? ?? const {};
    final abnormal = (parameters['abnormal'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    final newlyAdded = (parameters['newlyAdded'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    final existing = (parameters['existing'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();

    final trackedCount = abnormal.length + newlyAdded.length + existing.length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, careloopFabClearance),
        children: [
          // Stat cards — individual colored boxes matching the Vitals tab's box format, each
          // still tappable to scroll to its section. IntrinsicHeight + stretch keeps all three the
          // same height even when one label wraps to an extra line (narrower available width —
          // e.g. the Profile screen's left nav panel expanded — used to silently CLIP that label
          // instead of wrapping, since Text defaults to TextOverflow.clip when unset).
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                child: _StatBox(
                  icon: Icons.warning_rounded,
                  value: '${abnormal.length}',
                  label: 'Needs attention',
                  color: careloopBlush,
                  accent: careloopDanger,
                  onTap: () => _scrollTo(_needsAttentionKey),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _StatBox(
                  icon: Icons.add_rounded,
                  value: '${newlyAdded.length}',
                  label: 'Newly added',
                  color: careloopPeriwinkle,
                  accent: careloopInfo,
                  onTap: () => _scrollTo(_newlyAddedKey),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _StatBox(
                  icon: Icons.grid_view_rounded,
                  value: '$trackedCount',
                  label: 'All results',
                  color: careloopLavender,
                  accent: careloopSuccess,
                  onTap: () => _scrollTo(_allResultsKey),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          // Health insights agent — a plain-language, display-only summary of what changed since
          // last time. Never shown while empty/never-loaded.
          if (_insightLoading || _insight != null)
            SectionCard(
              title: 'Health insight',
              child: _insightLoading
                  ? const Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: careloopPrimary)),
                      SizedBox(width: 10),
                      Text('Looking at recent trends…', style: TextStyle(color: careloopMuted, fontSize: careloopTypeBody - 1)),
                    ])
                  : Text(_insight!, style: const TextStyle(color: careloopTextPrimary, fontSize: careloopTypeBody - 1, height: 1.5)),
            ),
          const SizedBox(height: 6),
          // Allergies & chronic conditions live on the Symptoms tab now, alongside the rest of
          // this member's self-reported health history.
          // Medications: ledger rows exactly per the design spec — name/dose left, "since" date
          // right in mono.
          LedgerTable(
            title: 'Current medications',
            rows: meds.isEmpty
                ? [LedgerRow(label: 'None on file', trailing: const SizedBox.shrink(), labelSize: careloopTypeBody - 1)]
                : [
                    for (final m in meds)
                      LedgerRow(
                        label: m['medicine_name'] ?? '',
                        sublabel: [m['dosage'], m['frequency'], m['duration']].where((e) => e != null).join(' · '),
                        trailing: const SizedBox.shrink(),
                        labelSize: careloopTypeBody - 1,
                        sublabelSize: careloopTypeCaption - 0.5,
                      ),
                  ],
          ),
          const SizedBox(height: 20),
          // Order per product decision: abnormal values first (can't be missed), then anything
          // tested for the first time in the latest upload, then everything else's latest value.
          // The review-queue confirmation gate is skipped here on purpose — see summary.ts.
          LedgerTable(
              key: _needsAttentionKey,
              title: 'Needs attention',
              rows: abnormal.isEmpty
                  ? [LedgerRow(label: 'Nothing out of range', trailing: const SizedBox.shrink(), labelSize: careloopTypeBody - 1)]
                  : [for (final p in abnormal) _paramRow(p)]),
          if (newlyAdded.isNotEmpty) ...[
            const SizedBox(height: 20),
            LedgerTable(key: _newlyAddedKey, title: 'Newly added', rows: [for (final p in newlyAdded) _paramRow(p)]),
          ],
          const SizedBox(height: 20),
          LedgerTable(
              key: _allResultsKey,
              title: 'All results',
              rows: existing.isEmpty
                  ? [LedgerRow(label: 'No other results on file', trailing: const SizedBox.shrink(), labelSize: careloopTypeBody - 1)]
                  : [for (final p in existing) _paramRow(p)]),
        ],
      ),
    );
  }
}

/// A colored stat box — same anatomy as Vitals' _VitalCard (icon badge, big value, label) so the
/// three Overview stats read as the same visual language as the rest of the app's metric cards.
class _StatBox extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final Color accent;
  final VoidCallback onTap;
  const _StatBox({required this.icon, required this.value, required this.label, required this.color, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(careloopRadiusMd),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder, boxShadow: careloopCardShadow),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, size: 14, color: accent),
            ),
            const SizedBox(height: 8),
            Text(value, style: careloopPageTitle().copyWith(fontSize: 24)),
            const SizedBox(height: 3),
            // No maxLines cap — Text defaults to TextOverflow.clip when unset, which silently cut
            // this label off at narrower widths instead of wrapping to a 3rd line.
            Text(label.toUpperCase(), style: TextStyle(color: accent, fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
          ],
        ),
      ),
    );
  }
}
