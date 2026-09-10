import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../auth_provider.dart';
import '../../../theme.dart';
import '../../../utils/motion.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/ledger.dart';
import '../../../widgets/section_card.dart';
import '../../../widgets/voice_language_button.dart';
import '../symptom_intake_screen.dart';

/// Symptoms & Observations tab (Roadmap Section 2.4's prerequisite) — a running, member-owned log
/// of how they've been feeling, each entry structured by the symptom intake agent through a short
/// clarifying Q&A rather than a form. Never shows a diagnosis or likelihood anywhere on this tab —
/// only what the member said and the dates/fields the agent structured from it.
class SymptomsTab extends StatefulWidget {
  final String memberId;
  const SymptomsTab({super.key, required this.memberId});
  @override
  State<SymptomsTab> createState() => _SymptomsTabState();
}

class _SymptomsTabState extends State<SymptomsTab> {
  List<dynamic>? _entries;
  List<dynamic>? _consultationHistory;
  Map<String, dynamic>? _summary;
  final _input = TextEditingController();
  final _allergy = TextEditingController();
  final _condition = TextEditingController();
  bool _starting = false;
  String? _translatedFrom;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final results = await Future.wait([api.getSymptomEntries(widget.memberId), api.getSummary(widget.memberId), api.getConsultationSymptomHistory(widget.memberId)]);
    if (mounted) {
      setState(() {
        _entries = results[0] as List<dynamic>;
        _summary = results[1] as Map<String, dynamic>;
        _consultationHistory = results[2] as List<dynamic>;
      });
    }
  }

  Future<void> _start() async {
    final text = _input.text.trim();
    if (text.isEmpty || _starting) return;
    setState(() => _starting = true);
    _input.clear();
    if (mounted) {
      await Navigator.push(context, pushRoute(SymptomIntakeScreen(memberId: widget.memberId, openingMessage: text)));
    }
    if (mounted) setState(() => _starting = false);
    _load();
  }

  Future<void> _openEntry(Map<String, dynamic> entry) async {
    await Navigator.push(context, pushRoute(SymptomIntakeScreen(memberId: widget.memberId, entryId: entry['id'] as String)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_entries == null || _summary == null || _consultationHistory == null) return const LoadingCenter();
    final api = context.read<AuthProvider>().api;
    // Merge the member's own self-logged entries with doctor-console-entered chief-complaint/
    // symptom history into one date-ordered timeline, each tagged by where it came from — two
    // separate backend stores (symptom_entries vs. consultation_notes), one combined view.
    final history = <_HistoryItem>[
      for (final e in _entries!.cast<Map<String, dynamic>>()) _HistoryItem.self(e),
      for (final c in _consultationHistory!.cast<Map<String, dynamic>>()) _HistoryItem.consultation(c),
    ]..sort((a, b) => b.date.compareTo(a.date));
    final allergies = _summary!['allergies'] as List<dynamic>;
    final conditions = _summary!['chronicConditions'] as List<dynamic>;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, careloopFabClearance),
        children: [
          // Moved here from the Overview tab — allergies and chronic conditions are self-reported
          // health background, a natural fit alongside the rest of this member's own health
          // history rather than the results-focused Overview tab.
          LedgerTable(
            title: 'Allergies',
            rows: allergies.isEmpty
                ? [LedgerRow(label: 'None recorded', trailing: const SizedBox.shrink(), labelSize: careloopTypeBody - 1)]
                : [for (final a in allergies) LedgerRow(label: a['value'] ?? '', trailing: const SizedBox.shrink(), labelSize: careloopTypeBody - 1)],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 20),
            child: Row(children: [
              Expanded(child: TextField(controller: _allergy, decoration: const InputDecoration(hintText: 'Add allergy'))),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () async {
                  if (_allergy.text.trim().isEmpty) return;
                  await api.addAllergy(widget.memberId, _allergy.text.trim());
                  _allergy.clear();
                  _load();
                },
                child: const Text('Add'),
              ),
            ]),
          ),
          LedgerTable(
            title: 'Chronic conditions',
            rows: conditions.isEmpty
                ? [LedgerRow(label: 'None recorded', trailing: const SizedBox.shrink(), labelSize: careloopTypeBody - 1)]
                : [for (final c in conditions) LedgerRow(label: c['value'] ?? '', trailing: const SizedBox.shrink(), labelSize: careloopTypeBody - 1)],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 20),
            child: Row(children: [
              Expanded(child: TextField(controller: _condition, decoration: const InputDecoration(hintText: 'Add condition'))),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () async {
                  if (_condition.text.trim().isEmpty) return;
                  await api.addChronicCondition(widget.memberId, _condition.text.trim());
                  _condition.clear();
                  _load();
                },
                child: const Text('Add'),
              ),
            ]),
          ),
          SectionCard(
            title: "Log how you're feeling",
            icon: Icons.edit_note_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  "Describe it in your own words — a few clarifying questions turn it into a clear, dated note. This never diagnoses; if anything feels urgent, contact a doctor right away.",
                  style: TextStyle(color: careloopMuted, fontSize: 11.5, height: 1.35),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: "e.g. I've had a dull headache since yesterday"),
                  onSubmitted: (_) => _start(),
                  onChanged: (_) => setState(() => _translatedFrom = null),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: VoiceLanguageButton(
                    onResult: (text, {translatedFrom}) => setState(() {
                      _input.text = text;
                      _translatedFrom = translatedFrom;
                    }),
                  ),
                ),
                if (_translatedFrom != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('Translated from $_translatedFrom', style: const TextStyle(color: careloopMutedDim, fontSize: 10.5, fontStyle: FontStyle.italic)),
                  ),
                const SizedBox(height: 10),
                ElevatedButton(onPressed: _starting ? null : _start, child: Text(_starting ? 'Starting…' : 'Start')),
              ],
            ),
          ),
          if (history.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: EmptyState(icon: Icons.sick_rounded, message: 'Nothing logged yet.'),
            )
          else
            LedgerTable(
              title: 'Logged entries',
              titleIcon: Icons.history_rounded,
              rows: [for (final h in history) _historyRow(h)],
            ),
        ],
      ),
    );
  }

  LedgerRow _historyRow(_HistoryItem h) {
    if (h.isFromConsultation) {
      return LedgerRow(
        label: h.label,
        sublabel: '${h.date.substring(0, 10)} · via consultation with ${h.providerName ?? 'your doctor'}',
        labelSize: careloopTypeBody - 1,
        sublabelSize: careloopTypeCaption - 0.5,
        trailing: const StatusPill('Dr. console', tone: PillTone.info),
      );
    }
    final e = h.raw;
    final urgent = e['urgent_flag'] == 1;
    final inProgress = e['status'] == 'in_progress';
    final severity = e['severity'] as String?;
    return LedgerRow(
      label: e['raw_description'] ?? '',
      sublabel: [h.date.substring(0, 10), if (severity != null && severity.isNotEmpty) severity, 'Manual'].join(' · '),
      labelSize: careloopTypeBody - 1,
      sublabelSize: careloopTypeCaption - 0.5,
      trailing: urgent
          ? const StatusPill('Urgent', tone: PillTone.danger)
          : inProgress
              ? const StatusPill('In progress', tone: PillTone.warning)
              : const Icon(Icons.chevron_right_rounded, color: careloopMuted),
      onTap: () => _openEntry(e),
    );
  }
}

/// One row in the merged Symptoms history — either the member's own self-logged entry
/// (`symptom_entries`) or a doctor's chief-complaint/symptoms from a consultation
/// (`consultation_notes`), normalized just enough to sort and render both the same way.
class _HistoryItem {
  final bool isFromConsultation;
  final String date;
  final String label;
  final String? providerName;
  final Map<String, dynamic> raw;
  _HistoryItem._({required this.isFromConsultation, required this.date, required this.label, this.providerName, required this.raw});

  factory _HistoryItem.self(Map<String, dynamic> e) => _HistoryItem._(isFromConsultation: false, date: e['created_at'] as String? ?? '', label: e['raw_description'] as String? ?? '', raw: e);

  factory _HistoryItem.consultation(Map<String, dynamic> c) {
    final complaint = (c['chief_complaint'] as String?)?.trim();
    final symptoms = (c['symptoms'] as List).cast<String>();
    final label = complaint?.isNotEmpty == true ? complaint! : symptoms.join(', ');
    return _HistoryItem._(
      isFromConsultation: true,
      date: c['visit_datetime'] as String? ?? c['created_at'] as String? ?? '',
      label: label,
      providerName: c['provider_name'] as String?,
      raw: c,
    );
  }
}
