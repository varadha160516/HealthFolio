import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../auth_provider.dart';
import '../../../theme.dart';
import '../../../utils/blood_groups.dart';
import '../../../utils/text_case.dart';
import '../../../widgets/section_card.dart';

/// A complete-repository-style profile: identity, contact/emergency info, care team, insurance,
/// and the member's latest vitals — the intent being that a family's whole medical picture lives
/// in this app, not just lab results (per product direction).
class ProfileTab extends StatefulWidget {
  final String memberId;
  const ProfileTab({super.key, required this.memberId});
  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  Map<String, dynamic>? _member;
  List<dynamic>? _insurance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final family = await api.getFamily();
    final member = (family['members'] as List<dynamic>).cast<Map<String, dynamic>>().firstWhere((m) => m['id'] == widget.memberId);
    final insurance = await api.getInsurance(widget.memberId);
    if (mounted) {
      setState(() {
        _member = member;
        _insurance = insurance;
      });
    }
  }

  int? _age(String? dob) {
    if (dob == null) return null;
    final d = DateTime.tryParse(dob);
    if (d == null) return null;
    return (DateTime.now().difference(d).inDays / 365.25).floor();
  }

  Future<void> _editFields(String title, List<_EditField> fields) async {
    final controllers = {for (final f in fields) f.key: TextEditingController(text: _member![f.key]?.toString() ?? '')};
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final f in fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: f.isDate
                      // Calendar picker for convenience, but still a plain TextField underneath
                      // so manual entry keeps working too.
                      ? TextField(
                          controller: controllers[f.key],
                          decoration: InputDecoration(
                            labelText: f.label,
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.calendar_month_rounded, size: 20),
                              onPressed: () async {
                                final now = DateTime.now();
                                final initial = DateTime.tryParse(controllers[f.key]!.text.trim()) ?? DateTime(now.year - 5);
                                final picked = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(1900), lastDate: now);
                                if (picked != null) controllers[f.key]!.text = picked.toIso8601String().substring(0, 10);
                              },
                            ),
                          ),
                        )
                      : f.options != null
                          ? DropdownButtonFormField<String>(
                              initialValue: controllers[f.key]!.text.isEmpty ? null : controllers[f.key]!.text,
                              decoration: InputDecoration(labelText: f.label),
                              items: [for (final o in f.options!) DropdownMenuItem(value: o.$1, child: Text(o.$2))],
                              onChanged: (v) => controllers[f.key]!.text = v ?? '',
                            )
                          : TextField(controller: controllers[f.key], decoration: InputDecoration(labelText: f.label)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    final payload = {for (final f in fields) f.key: controllers[f.key]!.text.trim()};
    await context.read<AuthProvider>().api.updateMemberProfile(widget.memberId, payload);
    _load();
  }

  Future<void> _addInsurance() async {
    final payer = TextEditingController();
    final policyNumber = TextEditingController();
    final sumInsured = TextEditingController();
    final periodStart = TextEditingController();
    final periodEnd = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add insurance policy'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: payer, decoration: const InputDecoration(labelText: 'Insurer / payer name')),
            const SizedBox(height: 8),
            TextField(controller: policyNumber, decoration: const InputDecoration(labelText: 'Policy number')),
            const SizedBox(height: 8),
            TextField(controller: sumInsured, decoration: const InputDecoration(labelText: 'Sum insured'), keyboardType: TextInputType.number),
            const SizedBox(height: 8),
            // Same calendar-picker pattern _editFields already uses for date of birth — just
            // newly applied here too, instead of expecting a hand-typed YYYY-MM-DD string.
            TextField(
              controller: periodStart,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Start date',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.calendar_month_rounded, size: 20),
                  onPressed: () async {
                    final now = DateTime.now();
                    final initial = DateTime.tryParse(periodStart.text.trim()) ?? now;
                    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(now.year - 5), lastDate: DateTime(now.year + 10));
                    if (picked != null) periodStart.text = picked.toIso8601String().substring(0, 10);
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: periodEnd,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Expiry date',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.calendar_month_rounded, size: 20),
                  onPressed: () async {
                    final now = DateTime.now();
                    final initial = DateTime.tryParse(periodEnd.text.trim()) ?? DateTime.tryParse(periodStart.text.trim()) ?? now;
                    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(now.year - 5), lastDate: DateTime(now.year + 10));
                    if (picked != null) periodEnd.text = picked.toIso8601String().substring(0, 10);
                  },
                ),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Add')),
        ],
      ),
    );
    if (saved != true || payer.text.trim().isEmpty || policyNumber.text.trim().isEmpty || !mounted) return;
    await context.read<AuthProvider>().api.addInsurance(widget.memberId, {
      'payer_name': payer.text.trim(),
      'policy_number': policyNumber.text.trim(),
      'sum_insured': double.tryParse(sumInsured.text.trim()),
      'period_start': periodStart.text.trim().isEmpty ? null : periodStart.text.trim(),
      'period_end': periodEnd.text.trim().isEmpty ? null : periodEnd.text.trim(),
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_member == null || _insurance == null) return const LoadingCenter();
    final m = _member!;
    final age = _age(m['dob'] as String?);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, careloopFabClearance),
        children: [
          _ProfileHero(name: m['name'] ?? '', relationship: capitalizeFirst((m['relationship_to_primary'] as String? ?? '').replaceAll('_', ' ')), age: age, bloodGroup: m['blood_group']),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Personal details',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _InfoRow('Name', m['name'], icon: Icons.person_rounded, iconBg: careloopAccentLight, iconColor: careloopAccent),
                _InfoRow('Relationship', capitalizeFirstOrNull((m['relationship_to_primary'] as String?)?.replaceAll('_', ' ')),
                    icon: Icons.people_alt_rounded, iconBg: careloopLavender, iconColor: careloopSuccess),
                _InfoRow('Date of birth', m['dob'], icon: Icons.calendar_month_rounded, iconBg: careloopTealBg, iconColor: careloopTeal),
                _InfoRow('Age', age != null ? '$age yrs' : null, icon: Icons.cake_rounded, iconBg: careloopTealBg, iconColor: careloopTeal),
                _InfoRow('Sex', capitalizeFirstOrNull(m['sex'] as String?), icon: Icons.wc_rounded, iconBg: careloopPeriwinkle, iconColor: careloopInfo),
                _InfoRow('Blood group', m['blood_group'], icon: Icons.water_drop_rounded, iconBg: careloopBlush, iconColor: careloopDanger),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: const Text('Edit'),
                    // The family coordinator's own relationship ('self') is fixed — the server
                    // rejects changing it, so it isn't offered here either.
                    onPressed: () => _editFields('Personal details', [
                      _EditField('name', 'Name'),
                      if (m['relationship_to_primary'] != 'self')
                        _EditField('relationship_to_primary', 'Relationship',
                            options: const [('spouse', 'Spouse'), ('child', 'Child'), ('parent', 'Parent'), ('other', 'Other')]),
                      _EditField('dob', 'Date of birth (YYYY-MM-DD)', isDate: true),
                      _EditField('sex', 'Sex', options: const [('male', 'Male'), ('female', 'Female'), ('other', 'Other')]),
                      _EditField('blood_group', 'Blood group', options: [for (final g in kBloodGroups) (g, g)]),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          SectionCard(
            title: 'Contact & emergency contact',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _InfoRow('Phone', m['phone'], icon: Icons.call_rounded, iconBg: careloopAccentLight, iconColor: careloopAccent),
                _InfoRow('Emergency contact', m['emergency_contact_name'], icon: Icons.person_rounded, iconBg: careloopLavender, iconColor: careloopSuccess),
                _InfoRow('Relationship', m['emergency_contact_relationship'], icon: Icons.people_alt_rounded, iconBg: careloopLavender, iconColor: careloopSuccess),
                // Blood group added here too (same field as Personal details above — editable
                // from either section) and Address now sits where Emergency phone used to.
                _InfoRow('Blood group', m['blood_group'], icon: Icons.water_drop_rounded, iconBg: careloopBlush, iconColor: careloopDanger),
                _InfoRow('Address', m['address'], icon: Icons.location_on_rounded, iconBg: careloopOrangeBg, iconColor: careloopOrange),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: const Text('Edit'),
                    onPressed: () => _editFields('Contact & emergency contact', [
                      _EditField('phone', 'Phone number'),
                      _EditField('emergency_contact_name', 'Emergency contact name'),
                      _EditField('emergency_contact_relationship', 'Relationship'),
                      _EditField('blood_group', 'Blood group', options: [for (final g in kBloodGroups) (g, g)]),
                      _EditField('address', 'Address'),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          // "Care team & directives" is intentionally not rendered, per request — the underlying
          // fields (primary_physician_name/phone, organ_donor_status) and their edit path via
          // _editFields still exist, this section just isn't shown here anymore.
          SectionCard(
            title: 'Insurance',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_insurance!.isEmpty) const Text('No policies on file.', style: TextStyle(color: careloopMuted)),
                for (final p in _insurance!.cast<Map<String, dynamic>>())
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${p['payer_name']} — ${p['policy_number']}'),
                    subtitle: Text([
                      if (p['sum_insured'] != null) 'Sum insured: ${p['sum_insured']}',
                      if (p['period_start'] != null || p['period_end'] != null)
                        '${_formatPolicyDate(p['period_start'] as String?)} – ${_formatPolicyDate(p['period_end'] as String?)}',
                    ].join(' · ')),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: careloopDanger),
                      onPressed: () async {
                        await context.read<AuthProvider>().api.deleteInsurance(p['id']);
                        _load();
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(icon: const Icon(Icons.add_rounded, size: 16), label: const Text('Add policy'), onPressed: _addInsurance),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatPolicyDate(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso);
  return d == null ? iso : DateFormat('d MMM yyyy').format(d);
}

class _EditField {
  final String key;
  final String label;
  final List<(String, String)>? options;
  final bool isDate;
  _EditField(this.key, this.label, {this.options, this.isDate = false});
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String? value;
  final IconData? icon;
  final Color? iconBg;
  final Color? iconColor;
  const _InfoRow(this.label, this.value, {this.icon, this.iconBg, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        if (icon != null) ...[
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: iconBg ?? careloopAccentLight, borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 13, color: iconColor ?? careloopAccent),
          ),
          const SizedBox(width: 10),
        ],
        // Both sides are flexible (not a fixed-width label) so they shrink together as the panel
        // narrows — a fixed-width label plus a narrow panel (e.g. the left nav expanded) used to
        // starve the value's Expanded down to near-zero width, which made Text wrap one character
        // per line instead of just wrapping normally or eliding.
        Expanded(
          flex: 2,
          child: Text(label, style: const TextStyle(color: careloopMuted, fontSize: 12, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: Text((value == null || value!.isEmpty) ? 'Not recorded' : value!,
              textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  final String name;
  final String relationship;
  final int? age;
  final String? bloodGroup;
  const _ProfileHero({required this.name, required this.relationship, required this.age, required this.bloodGroup});

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder),
      child: Row(children: [
        // The brand gradient, not the per-relationship color (colorForRelationship) — the
        // reference's header avatar is always the gradient, regardless of who the member is.
        Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: careloopPrimaryGradient),
            shape: BoxShape.circle,
          ),
          child: Center(child: Text(_initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 17))),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: careloopSectionHeading(color: careloopTextPrimary).copyWith(fontSize: 19), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 5, children: [
                if (relationship.isNotEmpty) _HeroChip(relationship),
                if (age != null) _HeroChip('$age yrs'),
                if (bloodGroup != null && bloodGroup!.isNotEmpty) _HeroChip(bloodGroup!),
              ]),
            ],
          ),
        ),
      ]),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final String label;
  const _HeroChip(this.label);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: careloopSurfaceRaised, borderRadius: BorderRadius.circular(careloopRadiusSm), border: Border.all(color: careloopBorder)),
      child: Text(label, style: const TextStyle(color: careloopMuted, fontSize: careloopTypeMicro, fontWeight: FontWeight.w500)),
    );
  }
}
