import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../auth_provider.dart';
import '../../../theme.dart';
import '../../../widgets/section_card.dart';

/// Vitals tab — manual entry of heart rate, blood pressure, respiratory rate, SpO2, temperature,
/// weight, height, and head circumference, plus growth percentiles (weight/height/BMI-for-age)
/// auto-calculated server-side from the latest entry against real CDC growth-chart reference data
/// (see server/src/pipeline/growthPercentile.ts) — never computed on-device, so there's exactly
/// one place that math lives.
class VitalsTab extends StatefulWidget {
  final String memberId;
  const VitalsTab({super.key, required this.memberId});
  @override
  State<VitalsTab> createState() => _VitalsTabState();
}

class _VitalsTabState extends State<VitalsTab> {
  List<dynamic>? _entries;
  Map<String, dynamic>? _growth;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final r = await api.getVitalsEntries(widget.memberId);
    if (mounted) {
      setState(() {
        _entries = r['entries'] as List<dynamic>;
        _growth = r['growth'] as Map<String, dynamic>?;
      });
    }
  }

  Future<void> _openEntrySheet() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _VitalsEntrySheet(memberId: widget.memberId),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_entries == null) return const LoadingCenter();
    final latest = _entries!.isEmpty ? null : _entries!.first as Map<String, dynamic>;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, careloopFabClearance),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionCaption('Vitals', icon: Icons.favorite_rounded),
                    Padding(
                      padding: const EdgeInsets.only(left: 2, bottom: 4),
                      child: Text(
                        latest != null ? 'Last updated: ${_formatWhen(latest['recorded_at'] as String)} · ${_source(latest)}' : 'No vitals recorded yet',
                        style: const TextStyle(color: careloopMuted, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(onPressed: _openEntrySheet, icon: const Icon(Icons.add_rounded, size: 16), label: const Text('Log vitals')),
            ],
          ),
          const SizedBox(height: 4),
          if (latest == null)
            const InfoBanner("Nothing logged yet — tap \"Log vitals\" to record heart rate, blood pressure, weight, and more.", info: true)
          else ...[
            _CardGrid(
              title: 'Core Vitals',
              icon: Icons.monitor_heart_rounded,
              items: [
                if (latest['systolic_bp'] != null || latest['diastolic_bp'] != null)
                  _VitalItem(
                      icon: Icons.favorite_rounded,
                      label: 'Blood Pressure',
                      value: '${_num(latest['systolic_bp'])}/${_num(latest['diastolic_bp'])}',
                      unit: 'mmHg',
                      color: careloopPeriwinkle),
                if (latest['heart_rate'] != null)
                  _VitalItem(icon: Icons.monitor_heart_rounded, label: 'Heart Rate', value: _num(latest['heart_rate']), unit: 'bpm', color: careloopBlush),
                if (latest['respiratory_rate'] != null)
                  _VitalItem(icon: Icons.air_rounded, label: 'Respiratory Rate', value: _num(latest['respiratory_rate']), unit: '/min', color: careloopLavender),
                if (latest['spo2'] != null) _VitalItem(icon: Icons.opacity_rounded, label: 'SpO2', value: _num(latest['spo2']), unit: '%', color: careloopCream),
                if (latest['temperature_f'] != null)
                  _VitalItem(icon: Icons.thermostat_rounded, label: 'Temperature', value: _num(latest['temperature_f']), unit: '°F', color: careloopLilac),
              ],
            ),
            const SizedBox(height: 16),
            _CardGrid(
              title: 'Growth',
              icon: Icons.child_care_rounded,
              items: [
                if (latest['weight_kg'] != null) _VitalItem(icon: Icons.monitor_weight_rounded, label: 'Weight', value: _num(latest['weight_kg']), unit: 'kg', color: careloopCream),
                if (latest['height_cm'] != null) _VitalItem(icon: Icons.height_rounded, label: 'Height', value: _num(latest['height_cm']), unit: 'cm', color: careloopPeriwinkle),
                if (latest['head_circumference_cm'] != null)
                  _VitalItem(icon: Icons.circle_outlined, label: 'Head Circumference', value: _num(latest['head_circumference_cm']), unit: 'cm', color: careloopLilac),
              ],
            ),
            const SizedBox(height: 16),
            _buildGrowthPercentileCard(),
            const SizedBox(height: 16),
            _buildHistory(),
          ],
        ],
      ),
    );
  }

  static String _source(Map<String, dynamic> entry) => entry['appointment_id'] != null ? 'via Dr. console' : 'Manual entry';

  Widget _buildHistory() {
    final entries = _entries!.cast<Map<String, dynamic>>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionCaption('History', icon: Icons.history_rounded),
        Container(
          decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder, boxShadow: careloopCardShadow),
          child: Column(
            children: [
              for (final (i, e) in entries.indexed) ...[
                if (i > 0) const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                  child: Row(children: [
                    Icon(e['appointment_id'] != null ? Icons.medical_services_outlined : Icons.person_outline_rounded, size: 15, color: careloopMuted),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_formatWhen(e['recorded_at'] as String), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                          Text(_source(e), style: const TextStyle(color: careloopMuted, fontSize: 10.5)),
                        ],
                      ),
                    ),
                  ]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGrowthPercentileCard() {
    final g = _growth;
    if (g == null) return const SizedBox.shrink();
    final items = <_VitalItem>[
      if (g['weightForAgePercentile'] != null)
        _VitalItem(icon: Icons.scale_rounded, label: 'Weight-for-age', value: '${g['weightForAgePercentile']}', unit: 'pct', color: careloopCream),
      if (g['heightForAgePercentile'] != null)
        _VitalItem(icon: Icons.straighten_rounded, label: 'Height-for-age', value: '${g['heightForAgePercentile']}', unit: 'pct', color: careloopPeriwinkle),
      if (g['bmiForAgePercentile'] != null)
        _VitalItem(icon: Icons.pie_chart_rounded, label: 'BMI-for-age', value: '${g['bmiForAgePercentile']}', unit: 'pct', color: careloopLavender),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionCaption('Growth Percentiles', icon: Icons.insights_rounded),
        if (items.isNotEmpty) _CardGridBody(items: items),
        if (g['note'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 2),
            child: Text('${g['note']}', style: const TextStyle(color: careloopMuted, fontSize: 11.5, fontStyle: FontStyle.italic, height: 1.3)),
          ),
        if (items.isEmpty && g['note'] == null)
          const Padding(padding: EdgeInsets.only(left: 2), child: Text('Log weight and height to see growth percentiles.', style: TextStyle(color: careloopMuted, fontSize: 12.5))),
        const Padding(
          padding: EdgeInsets.only(top: 6, left: 2),
          child: Text('Auto-calculated from the CDC 2000 growth chart reference data — updates whenever new weight/height is logged.', style: TextStyle(color: careloopMuted, fontSize: 11, height: 1.3)),
        ),
      ],
    );
  }

  static String _num(dynamic v) => v == null ? '—' : (v is num && v == v.roundToDouble() ? v.toInt().toString() : '$v');

  static String _formatWhen(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    return DateFormat('MMM d, yyyy · h:mm a').format(dt);
  }
}

class _VitalItem {
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final Color color;
  _VitalItem({required this.icon, required this.label, required this.value, required this.unit, this.color = careloopSurface});
}

/// A titled card grid — used for Core Vitals / Growth. Items wrap two-per-row; an odd item out
/// spans the full width (matches the approved Vitals mockup's "Weight — spans full width" card).
class _CardGrid extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<_VitalItem> items;
  const _CardGrid({required this.title, required this.icon, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCaption(title, icon: icon),
        _CardGridBody(items: items),
      ],
    );
  }
}

class _CardGridBody extends StatelessWidget {
  final List<_VitalItem> items;
  const _CardGridBody({required this.items});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      final hasSecond = i + 1 < items.length;
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _VitalCard(item: items[i])),
          if (hasSecond) ...[const SizedBox(width: 10), Expanded(child: _VitalCard(item: items[i + 1]))],
        ]),
      ));
    }
    return Column(children: rows);
  }
}

class _VitalCard extends StatelessWidget {
  final _VitalItem item;
  const _VitalCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: item.color, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder, boxShadow: careloopCardShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(9)),
            child: Icon(item.icon, size: 14, color: careloopPrimary),
          ),
          const SizedBox(height: 9),
          // 600, matching careloopDataInline's own default weight for a health value.
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Flexible(child: Text(item.value, style: careloopDataInline(size: 16.5), overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 3),
            Text(item.unit, style: const TextStyle(color: careloopMuted, fontSize: 10.5, fontWeight: FontWeight.w500)),
          ]),
          const SizedBox(height: 4),
          Text(item.label, style: const TextStyle(color: careloopMuted, fontSize: 10.5, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// The manual-entry form — a bottom sheet with the same two groupings the display cards use
/// (Core Vitals, Growth), a "when was this taken" date/time picker, and one Save that posts a
/// single new member_vitals_entries row.
class _VitalsEntrySheet extends StatefulWidget {
  final String memberId;
  const _VitalsEntrySheet({required this.memberId});
  @override
  State<_VitalsEntrySheet> createState() => _VitalsEntrySheetState();
}

class _VitalsEntrySheetState extends State<_VitalsEntrySheet> {
  DateTime _when = DateTime.now();
  final _heartRate = TextEditingController();
  final _systolic = TextEditingController();
  final _diastolic = TextEditingController();
  final _respRate = TextEditingController();
  final _spo2 = TextEditingController();
  final _temp = TextEditingController();
  final _weight = TextEditingController();
  final _height = TextEditingController();
  final _headCirc = TextEditingController();
  bool _saving = false;

  Future<void> _pickWhen() async {
    final date = await showDatePicker(context: context, initialDate: _when, firstDate: DateTime(2000), lastDate: DateTime.now());
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when));
    if (time == null || !mounted) return;
    setState(() => _when = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    final payload = {
      'recorded_at': _when.toUtc().toIso8601String(),
      'heart_rate': _heartRate.text.trim(),
      'systolic_bp': _systolic.text.trim(),
      'diastolic_bp': _diastolic.text.trim(),
      'respiratory_rate': _respRate.text.trim(),
      'spo2': _spo2.text.trim(),
      'temperature_f': _temp.text.trim(),
      'weight_kg': _weight.text.trim(),
      'height_cm': _height.text.trim(),
      'head_circumference_cm': _headCirc.text.trim(),
    };
    if (payload.values.every((v) => v == '' || v == payload['recorded_at'])) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter at least one value.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final api = context.read<AuthProvider>().api;
      await api.addVitalsEntry(widget.memberId, payload);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String label, TextEditingController c, {String? suffix}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, suffixText: suffix),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        builder: (_, controller) => ListView(
          controller: controller,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Log vitals', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: careloopTextPrimary)),
                TextButton.icon(
                  onPressed: _pickWhen,
                  icon: const Icon(Icons.schedule_rounded, size: 16),
                  label: Text(DateFormat('MMM d, y · h:mm a').format(_when)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const SectionCaption('Core Vitals', icon: Icons.monitor_heart_rounded),
            _field('Heart rate', _heartRate, suffix: 'bpm'),
            Row(children: [
              Expanded(child: _field('Systolic BP', _systolic, suffix: 'mmHg')),
              const SizedBox(width: 8),
              Expanded(child: _field('Diastolic BP', _diastolic, suffix: 'mmHg')),
            ]),
            _field('Respiratory rate', _respRate, suffix: '/min'),
            _field('SpO2', _spo2, suffix: '%'),
            _field('Temperature', _temp, suffix: '°F'),
            const SizedBox(height: 6),
            const SectionCaption('Growth', icon: Icons.child_care_rounded),
            _field('Weight', _weight, suffix: 'kg'),
            _field('Height', _height, suffix: 'cm'),
            _field('Head circumference', _headCirc, suffix: 'cm'),
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Growth percentiles are calculated automatically from weight and height once saved.', style: TextStyle(color: careloopMuted, fontSize: 12, height: 1.3)),
            ),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)) : const Text('Save'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
