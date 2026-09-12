import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../auth_provider.dart';
import '../../theme.dart';
import '../../utils/blood_groups.dart';
import '../../utils/medication_schedule_infer.dart';
import '../../utils/motion.dart';
import '../../utils/text_case.dart';
import '../../widgets/section_card.dart';
import '../../widgets/liquid_glass.dart';
import 'member_profile_screen.dart';

// Rotated across the family list so each member card reads as its own distinct pastel surface,
// per the brief ("different pastel surfaces for different ... cards").
const _kMemberCardPastels = [careloopLavender, careloopPeriwinkle, careloopBlush, careloopCream, careloopLilac];

class FamilyDashboardScreen extends StatefulWidget {
  const FamilyDashboardScreen({super.key});
  @override
  State<FamilyDashboardScreen> createState() => _FamilyDashboardScreenState();
}

class _FamilyDashboardScreenState extends State<FamilyDashboardScreen> {
  List<dynamic>? _members;
  List<dynamic>? _reminders;
  bool _remindersLoading = false;
  List<dynamic>? _medReminders;
  List<dynamic>? _safetyFlags;
  bool _showAdd = false;
  final _name = TextEditingController();
  final _dob = TextEditingController();
  String? _bloodGroup;
  String _relationship = 'child';
  String? _sex;

  List<dynamic>? _archivedMembers;
  bool _showArchived = false;
  bool _archivedLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final f = await api.getFamily();
    final members = (f['members'] as List<dynamic>).cast<Map<String, dynamic>>();
    // Self always leads the list, family members follow in whatever order the API returned them.
    members.sort((a, b) {
      final aSelf = a['relationship_to_primary'] == 'self';
      final bSelf = b['relationship_to_primary'] == 'self';
      if (aSelf == bSelf) return 0;
      return aSelf ? -1 : 1;
    });
    if (mounted) setState(() => _members = members);
    _loadReminders();
    _loadMedReminders();
    _loadSafetyFlags();
  }

  /// Cross-provider safety net summary — how many members have an open flag, across every doctor
  /// and lab test on file, not just what one visit's own summary card would show. Fails silently,
  /// same reasoning as the other Home Screen cards.
  Future<void> _loadSafetyFlags() async {
    try {
      final api = context.read<AuthProvider>().api;
      final r = await api.getFamilySafetyFlagsSummary();
      if (mounted) setState(() => _safetyFlags = r);
    } catch (_) {
      // silent — see doc comment above
    }
  }

  /// Today's due/upcoming doses across the whole family — shown on Home so a reminder doesn't
  /// require opening each member's Medications tab individually. Fails silently, same reasoning
  /// as the care-coordinator reminders above: nice-to-have, never blocks the dashboard.
  Future<void> _loadMedReminders() async {
    try {
      final api = context.read<AuthProvider>().api;
      final r = await api.getFamilyMedicationsToday();
      if (mounted) setState(() => _medReminders = r);
    } catch (_) {
      // silent — see doc comment above
    }
  }

  /// Family care-coordinator agent (Roadmap Section 2.3) — fetched separately and never blocks
  /// the member list, same reasoning as the Overview tab's health insight card: nice-to-have,
  /// fails silently.
  Future<void> _loadReminders() async {
    final api = context.read<AuthProvider>().api;
    setState(() => _remindersLoading = true);
    try {
      final r = await api.getCareReminders();
      if (mounted) setState(() => _reminders = r);
    } catch (_) {
      // silent — see doc comment above
    } finally {
      if (mounted) setState(() => _remindersLoading = false);
    }
  }

  Future<void> _loadArchived() async {
    setState(() => _archivedLoading = true);
    try {
      final api = context.read<AuthProvider>().api;
      final f = await api.getFamily(includeArchived: true);
      final all = f['members'] as List<dynamic>;
      if (mounted) setState(() => _archivedMembers = all.cast<Map<String, dynamic>>().where((m) => m['archived_at'] != null).toList());
    } finally {
      if (mounted) setState(() => _archivedLoading = false);
    }
  }

  Future<void> _restore(Map<String, dynamic> member) async {
    final api = context.read<AuthProvider>().api;
    await api.restoreMember(member['id'] as String);
    _load();
    _loadArchived();
  }

  int _age(String? dob) {
    if (dob == null) return 0;
    final d = DateTime.tryParse(dob);
    if (d == null) return 0;
    return (DateTime.now().difference(d).inDays / 365.25).floor();
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  Future<void> _addMember() async {
    final api = context.read<AuthProvider>().api;
    await api.addMember({
      'name': _name.text.trim(),
      'dob': _dob.text.trim().isEmpty ? null : _dob.text.trim(),
      'sex': _sex,
      'blood_group': _bloodGroup,
      'relationship_to_primary': _relationship,
    });
    _name.clear();
    _dob.clear();
    setState(() {
      _bloodGroup = null;
      _showAdd = false;
    });
    _load();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(_dob.text.trim()) ?? DateTime(now.year - 5);
    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(1900), lastDate: now);
    if (picked != null) setState(() => _dob.text = picked.toIso8601String().substring(0, 10));
  }

  @override
  Widget build(BuildContext context) {
    if (_members == null) return const LoadingCenter();
    // Self's own current name, not the session's login-time displayName — the session is fetched
    // once at login and never updates, so it would go stale the moment Self's name is edited in
    // Profile. _members is self-first (see _load) and refetched every time this screen reloads
    // (including on returning from a member's profile — see the member-card onTap below), so
    // reading it from here keeps the welcome note dynamic and never stale.
    final selfName = _members!.isNotEmpty ? _members!.first['name'] as String? : context.watch<AuthProvider>().session?.displayName;
    // Liquid-glass treatment, this screen only: soft color blobs behind the scroll content, with
    // every card as a frosted, blurred glass pane over them instead of a flat pastel fill. The app
    // bar/bottom nav/FAB are shared chrome (owned by HomeShell) and stay as they are elsewhere.
    return Stack(children: [
      const Positioned.fill(child: LiquidBlobBackground()),
      _buildContent(context, selfName),
    ]);
  }

  Widget _buildContent(BuildContext context, String? selfName) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, careloopFabClearance),
        children: [
          if (selfName != null && selfName.isNotEmpty) ...[
            // 1: this is now the big heading — "Your family" below shrinks to a small label.
            Text('Welcome, $selfName!', style: careloopPageTitle().copyWith(fontSize: 28)),
            const SizedBox(height: 4),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('YOUR FAMILY', style: careloopEyebrow()),
              _AddButton(showing: _showAdd, onTap: () => setState(() => _showAdd = !_showAdd)),
            ],
          ),
          const SizedBox(height: 6),
          Text('${_members!.length} ${_members!.length == 1 ? 'member' : 'members'} in your care', style: const TextStyle(color: careloopMuted, fontSize: 13.5, fontWeight: FontWeight.w400)),
          const SizedBox(height: 14),
          // Care reminders — never shown while empty/never-loaded, same rule as the Overview
          // tab's health insight card. Glass pane instead of SectionCard's flat pastel fill.
          if (_remindersLoading || (_reminders?.isNotEmpty ?? false))
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: GlassPane(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.notifications_active_rounded, size: 16, color: careloopAccent),
                      const SizedBox(width: 8),
                      Text('Care reminders', style: careloopSectionHeading()),
                    ]),
                    const SizedBox(height: 10),
                    _remindersLoading && _reminders == null
                        ? const Row(mainAxisSize: MainAxisSize.min, children: [
                            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: careloopPrimary)),
                            SizedBox(width: 10),
                            Text('Checking checkups, meds, and vaccinations…', style: TextStyle(color: careloopMuted, fontSize: careloopTypeBody)),
                          ])
                        : Column(
                            children: [
                              for (final (i, r) in _reminders!.cast<Map<String, dynamic>>().indexed) ...[
                                if (i > 0) const SizedBox(height: 10),
                                _ReminderTile(reminder: r),
                              ],
                            ],
                          ),
                  ],
                ),
              ),
            ),
          // Medication reminders — today's due/upcoming doses across the family, moved here from
          // the Medications tab so a member sees what's due without opening each person's tab.
          if (_medReminders?.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: GlassPane(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.medication_rounded, size: 16, color: careloopAccent),
                      const SizedBox(width: 8),
                      Text('Medication reminders', style: careloopSectionHeading()),
                    ]),
                    const SizedBox(height: 10),
                    Column(
                      children: [
                        for (final (i, r) in _medReminders!.cast<Map<String, dynamic>>().indexed) ...[
                          if (i > 0) const SizedBox(height: 10),
                          _MedReminderTile(reminder: r),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          // Cross-provider safety net — flags computed across EVERY doctor and lab test on a
          // member's record, something no single provider's own view can show (see
          // safety_check_tab.dart). Tapping a row deep-links straight into that member's Safety
          // Check section instead of landing on Profile.
          if (_safetyFlags?.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: GlassPane(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.verified_user_rounded, size: 16, color: careloopAccent),
                      const SizedBox(width: 8),
                      Text('Health safety check', style: careloopSectionHeading()),
                    ]),
                    const SizedBox(height: 10),
                    Column(
                      children: [
                        for (final (i, s) in _safetyFlags!.cast<Map<String, dynamic>>().indexed) ...[
                          if (i > 0) const SizedBox(height: 10),
                          _SafetyFlagSummaryTile(
                            summary: s,
                            onTap: () async {
                              final member = _members!.cast<Map<String, dynamic>>().firstWhere((m) => m['id'] == s['memberId'], orElse: () => {'id': s['memberId'], 'name': s['memberName']});
                              await Navigator.push(context, pushRoute(MemberProfileScreen(member: member, initialIndex: kSafetyCheckTabIndex)));
                              if (mounted) _loadSafetyFlags();
                            },
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (_showAdd)
            SectionCard(
              title: 'Add a dependent',
              icon: Icons.person_add_alt_1_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _relationship,
                    decoration: const InputDecoration(labelText: 'Relationship'),
                    items: const [
                      DropdownMenuItem(value: 'spouse', child: Text('Spouse')),
                      DropdownMenuItem(value: 'child', child: Text('Child')),
                      DropdownMenuItem(value: 'parent', child: Text('Parent')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (v) => setState(() => _relationship = v ?? 'child'),
                  ),
                  const SizedBox(height: 10),
                  // Calendar picker for convenience, but the field stays a plain TextField so
                  // manual entry (typing the date directly) still works too.
                  TextField(
                    controller: _dob,
                    decoration: InputDecoration(
                      labelText: 'Date of birth (YYYY-MM-DD)',
                      suffixIcon: IconButton(icon: const Icon(Icons.calendar_month_rounded, size: 20), onPressed: _pickDob),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _sex,
                    decoration: const InputDecoration(labelText: 'Sex'),
                    items: const [
                      DropdownMenuItem(value: 'male', child: Text('Male')),
                      DropdownMenuItem(value: 'female', child: Text('Female')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (v) => setState(() => _sex = v),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _bloodGroup,
                    decoration: const InputDecoration(labelText: 'Blood group'),
                    items: [for (final g in kBloodGroups) DropdownMenuItem(value: g, child: Text(g))],
                    onChanged: (v) => setState(() => _bloodGroup = v),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton(onPressed: _addMember, child: const Text('Add to family')),
                ],
              ),
            ),
          for (final (i, m) in _members!.cast<Map<String, dynamic>>().indexed)
            FadeInUp(
              index: i,
              child: _MemberCard(
                member: m,
                age: _age(m['dob'] as String?),
                initials: _initials(m['name'] ?? '?'),
                cardColor: _kMemberCardPastels[i % _kMemberCardPastels.length],
                // 3: refetch on return — a member's profile (name, DOB, ...) may have changed
                // while we were away, so the dashboard (including the welcome note above, which
                // reads Self's name straight from this same list) needs fresh data the moment the
                // member navigates back, not whenever this screen next happens to reload.
                onTap: () async {
                  await Navigator.push(context, pushRoute(MemberProfileScreen(member: m)));
                  if (!mounted) return;
                  _load();
                  if (_showArchived) _loadArchived();
                },
              ),
            ),
          const SizedBox(height: 4),
          Center(
            child: TextButton.icon(
              onPressed: () {
                setState(() => _showArchived = !_showArchived);
                if (_showArchived && _archivedMembers == null) _loadArchived();
              },
              icon: Icon(_showArchived ? Icons.expand_less_rounded : Icons.archive_outlined, size: 17, color: careloopMuted),
              label: Text(_showArchived ? 'Hide archived' : 'Archived members', style: const TextStyle(color: careloopMuted, fontWeight: FontWeight.w500, fontSize: 13)),
            ),
          ),
          if (_showArchived) ...[
            if (_archivedLoading)
              const Padding(padding: EdgeInsets.only(top: 8), child: Center(child: CircularProgressIndicator(color: careloopPrimary)))
            else if ((_archivedMembers ?? const []).isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4, bottom: 8),
                child: Center(child: Text('No archived members.', style: TextStyle(color: careloopMuted, fontSize: 13))),
              )
            else
              for (final m in _archivedMembers!.cast<Map<String, dynamic>>())
                _ArchivedMemberRow(member: m, onRestore: () => _restore(m)),
          ],
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final bool showing;
  final VoidCallback onTap;
  const _AddButton({required this.showing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // The one brass primary action on this screen (Section 3.5) — never a pill, careloopRadiusSm
    // like every other button in the system.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(careloopRadiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: showing ? careloopSurfaceRaised : careloopSage,
          borderRadius: BorderRadius.circular(careloopRadiusSm),
          border: showing ? Border.all(color: careloopBorder) : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(showing ? Icons.close_rounded : Icons.add_rounded, size: 17, color: showing ? careloopMuted : careloopOnSage),
          const SizedBox(width: 4),
          Text(showing ? 'Cancel' : 'Add', style: TextStyle(color: showing ? careloopMuted : careloopOnSage, fontWeight: FontWeight.w500, fontSize: 13.5)),
        ]),
      ),
    );
  }
}

/// One family member's open-flag count from GET /family/safety-flags-summary.
class _SafetyFlagSummaryTile extends StatelessWidget {
  final Map<String, dynamic> summary;
  final VoidCallback onTap;
  const _SafetyFlagSummaryTile({required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final count = summary['openCount'] as int;
    return InkWell(
      borderRadius: BorderRadius.circular(careloopRadiusSm),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: careloopWarningBg, borderRadius: BorderRadius.circular(careloopRadiusSm)),
        child: Row(children: [
          const Icon(Icons.warning_amber_rounded, size: 17, color: careloopWarning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${summary['memberName']} — $count item${count == 1 ? '' : 's'} worth reviewing',
              style: const TextStyle(color: careloopWarning, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const Icon(Icons.chevron_right_rounded, size: 18, color: careloopWarning),
        ]),
      ),
    );
  }
}

/// One due/upcoming dose from GET /family/medications-today — tinted by whether it's already due
/// (red) or still coming up later today (blue), same solid-pill color language as the rest of the
/// dashboard's tiles.
class _MedReminderTile extends StatelessWidget {
  final Map<String, dynamic> reminder;
  const _MedReminderTile({required this.reminder});

  @override
  Widget build(BuildContext context) {
    final due = reminder['status'] == 'due';
    final fg = due ? careloopDanger : careloopInfo;
    final bg = due ? careloopAbnormalBg : careloopNewBg;
    final dose = [reminder['medicine_name'], reminder['dose_amount']].where((v) => v != null && (v as String).isNotEmpty).join(' — ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(careloopRadiusSm)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.medication_rounded, size: 17, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${reminder['member_name']} — $dose', style: TextStyle(color: fg, fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w600)),
                Text(due ? 'Due ${formatTime(reminder['time'] as String)}' : formatTime(reminder['time'] as String), style: TextStyle(color: fg.withValues(alpha: 0.8), fontSize: 11.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One line from the family care-coordinator agent — a checkup, refill, or vaccination check
/// that needs attention. Tinted by urgency (red once something's actually overdue, amber for a
/// medication about to run out), same solid-pill color language as StatusPill/LedgerFlag.
class _ReminderTile extends StatelessWidget {
  final Map<String, dynamic> reminder;
  const _ReminderTile({required this.reminder});

  IconData get _icon => switch (reminder['kind']) {
        'medication_refill' => Icons.medication_rounded,
        'vaccination_check' => Icons.vaccines_rounded,
        _ => Icons.event_busy_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final overdue = reminder['urgency'] == 'overdue';
    final fg = overdue ? careloopDanger : careloopWarning;
    final bg = overdue ? careloopAbnormalBg : careloopWarningBg;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(careloopRadiusSm)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon, size: 17, color: fg),
          const SizedBox(width: 10),
          Expanded(child: Text(reminder['message'] ?? '', style: TextStyle(color: fg, fontSize: 13.5, height: 1.5, fontWeight: FontWeight.w400))),
        ],
      ),
    );
  }
}

/// The "passport card" (design spec Section 3.2): a circular green-l initials badge, bordered
/// card like an index card in a passport wallet, name plus relationship/age as plain descriptive
/// text — not a colored tag, this system reserves color for structure and semantic flags, not
/// decoration.
class _MemberCard extends StatelessWidget {
  final Map<String, dynamic> member;
  final int age;
  final String initials;
  final Color cardColor;
  final VoidCallback onTap;
  const _MemberCard({required this.member, required this.age, required this.initials, required this.cardColor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final relationship = capitalizeFirst((member['relationship_to_primary'] as String? ?? '').replaceAll('_', ' '));
    final meta = [
      if (relationship.isNotEmpty) relationship,
      '$age yrs',
      if (member['blood_group'] != null && (member['blood_group'] as String).isNotEmpty) member['blood_group'],
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: GlassPane(
        radius: careloopRadiusMd,
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(careloopRadiusMd),
          child: InkWell(
            borderRadius: BorderRadius.circular(careloopRadiusMd),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: cardColor.withValues(alpha: 0.9), shape: BoxShape.circle),
                  child: Center(child: Text(initials, style: const TextStyle(color: careloopTextPrimary, fontWeight: FontWeight.w600, fontSize: 17))),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(member['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5, color: careloopTextPrimary)),
                    const SizedBox(height: 4),
                    Text(meta, style: const TextStyle(color: careloopMuted, fontSize: careloopTypeCaption, fontWeight: FontWeight.w400)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: careloopMuted),
            ]),
          ),
        ),
      ),
    ),
    );
  }
}

/// A restorable row for a member the coordinator previously archived — deliberately plain (no
/// avatar, no chevron-to-profile) since this list exists purely to undo a mistake, not to browse.
class _ArchivedMemberRow extends StatelessWidget {
  final Map<String, dynamic> member;
  final VoidCallback onRestore;
  const _ArchivedMemberRow({required this.member, required this.onRestore});

  @override
  Widget build(BuildContext context) {
    final relationship = capitalizeFirst((member['relationship_to_primary'] as String? ?? '').replaceAll('_', ' '));
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(member['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: careloopTextPrimary)),
              if (relationship.isNotEmpty) Text(relationship, style: const TextStyle(color: careloopMuted, fontSize: careloopTypeCaption)),
            ],
          ),
        ),
        TextButton(onPressed: onRestore, child: const Text('Restore')),
      ]),
    );
  }
}
