import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../auth_provider.dart';
import '../../../theme.dart';
import '../../../utils/medication_schedule_infer.dart';

String? _computeEndDate(String startDate, String? duration) {
  final d = (duration ?? '').toLowerCase();
  final match = RegExp(r'(\d+)\s*(day|week)').firstMatch(d);
  if (match == null) return null;
  final n = int.tryParse(match.group(1)!) ?? 0;
  if (n <= 0) return null;
  final unit = match.group(2);
  final start = DateTime.tryParse(startDate);
  if (start == null) return null;
  final end = start.add(Duration(days: unit == 'week' ? n * 7 : n));
  return end.toIso8601String().substring(0, 10);
}

/// The safety gate the request calls out explicitly: nothing extracted gets added without this
/// screen. Each line item defaults checked; unchecking one just leaves it out of "Add selected".
class PrescriptionReviewScreen extends StatefulWidget {
  final String memberId;
  final String documentId;
  const PrescriptionReviewScreen({super.key, required this.memberId, required this.documentId});

  @override
  State<PrescriptionReviewScreen> createState() => _PrescriptionReviewScreenState();
}

class _PrescriptionReviewScreenState extends State<PrescriptionReviewScreen> {
  Map<String, dynamic>? _doc;
  final Set<int> _unchecked = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final doc = await api.getDocument(widget.documentId);
    if (mounted) setState(() => _doc = doc);
  }

  Future<void> _addSelected(List<Map<String, dynamic>> items) async {
    setState(() => _busy = true);
    final api = context.read<AuthProvider>().api;
    final prescription = _doc!['prescription'] as Map<String, dynamic>?;
    final startDate = (prescription?['issued_at'] as String?)?.substring(0, 10) ?? DateTime.now().toIso8601String().substring(0, 10);
    var added = 0;
    try {
      for (var i = 0; i < items.length; i++) {
        if (_unchecked.contains(i)) continue;
        final item = items[i];
        final (frequency, times) = inferMedicationSchedule(item['frequency'] as String?);
        await api.addMedication(widget.memberId, {
          'medicine_name': item['medicine_name'],
          'strength': item['strength'],
          'dose_amount': item['dosage'],
          'frequency': frequency,
          'times': times,
          'start_date': startDate,
          'end_date': _computeEndDate(startDate, item['duration'] as String?),
          'purpose': prescription?['diagnosis_text'],
          'prescription_line_item_id': item['id'],
        });
        added++;
      }
      if (mounted) Navigator.of(context).pop(added);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_doc == null) return const Scaffold(backgroundColor: careloopBg, body: Center(child: CircularProgressIndicator()));
    final items = ((_doc!['prescriptionLineItems'] as List?) ?? const []).cast<Map<String, dynamic>>();

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
                  child: Container(width: 34, height: 34, decoration: BoxDecoration(color: careloopSurface, shape: BoxShape.circle, border: careloopCardBorder), child: const Icon(Icons.close_rounded, size: 16)),
                ),
                const SizedBox(width: 10),
                Text('Prescription found', style: careloopSectionHeading().copyWith(fontSize: 17)),
              ]),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const Expanded(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text("We couldn't find any medicines on this document — you can add them manually instead.", textAlign: TextAlign.center, style: TextStyle(color: careloopMuted)),
                    ),
                  ),
                )
              else ...[
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: careloopGreenBg, borderRadius: BorderRadius.circular(999)),
                    child: Text('We found ${items.length} medication${items.length == 1 ? '' : 's'}', style: const TextStyle(color: careloopGreen, fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final item = items[i];
                      final checked = !_unchecked.contains(i);
                      final (frequency, times) = inferMedicationSchedule(item['frequency'] as String?);
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder, boxShadow: careloopCardShadow),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Checkbox(
                            value: checked,
                            onChanged: (v) => setState(() => v == true ? _unchecked.remove(i) : _unchecked.add(i)),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item['medicine_name'] ?? 'Unnamed medicine', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                                const SizedBox(height: 2),
                                Text(
                                  [item['strength'], item['dosage'], item['duration']].where((v) => v != null && (v as String).isNotEmpty).join(' · '),
                                  style: const TextStyle(color: careloopMuted, fontSize: 11),
                                ),
                                const SizedBox(height: 2),
                                Text('As entered: ${frequencyLabel(frequency, times, null)}', style: const TextStyle(color: careloopAccent, fontSize: 10.5, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ]),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: () => Navigator.of(context).pop(0), child: const Text('Not now')),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _busy || items.length == _unchecked.length ? null : () => _addSelected(items),
                  child: Text(_busy ? 'Adding…' : 'Add ${items.length - _unchecked.length} selected'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
