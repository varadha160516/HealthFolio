import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../auth_provider.dart';
import '../../theme.dart';
import '../../utils/specializations.dart';
import '../../widgets/ledger.dart';
import '../../widgets/section_card.dart';
import '../../widgets/searchable_picker.dart';

enum _LocationStatus { idle, loading, denied, serviceOff, error, ready }

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});
  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  List<dynamic>? _appointments;
  List<dynamic>? _members;
  String? _memberId;

  String? _specialty;
  List<dynamic> _preferredForSpecialty = [];
  List<dynamic> _nearby = [];
  _LocationStatus _locationStatus = _LocationStatus.idle;
  final Set<String> _preferredProviderIds = {}; // across ALL specialties, for the star toggle state

  // Manual name search — the alternative to browsing by specialty, for a member who already knows
  // roughly who they want to book (textbox + live dropdown of matches).
  final _nameSearch = TextEditingController();
  List<dynamic> _nameSearchResults = [];
  bool _searchingByName = false;

  String? _selectedProviderId;
  Map<String, dynamic>? _selectedProvider;
  DateTime? _datetime;
  String _sharingPreference = 'full_history';
  final _reasonForVisit = TextEditingController();
  bool _booking = false;
  bool _appointmentsExpanded = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final appts = await api.getAppointments();
    final family = await api.getFamily();
    if (!mounted) return;
    setState(() {
      _appointments = appts;
      _members = family['members'] as List<dynamic>;
      _memberId ??= _members!.isNotEmpty ? _members!.first['id'] : null;
    });
    if (_memberId != null) await _loadPreferredIds();
  }

  Future<void> _loadPreferredIds() async {
    final api = context.read<AuthProvider>().api;
    final all = await api.getPreferredProviders(_memberId!);
    if (!mounted) return;
    setState(() {
      _preferredProviderIds
        ..clear()
        ..addAll(all.map((p) => p['id'] as String));
      _preferredForSpecialty = _specialty == null ? [] : all.where((p) => p['specialty'] == _specialty).toList();
    });
  }

  Future<void> _pickSpecialty() async {
    final picked = await showSearchablePicker(context: context, title: 'Choose a specialization', options: kSpecializations, selected: _specialty);
    if (picked == null) return;
    setState(() {
      _specialty = picked;
      _selectedProviderId = null;
      _selectedProvider = null;
      _nearby = [];
      _preferredForSpecialty = [];
      _nameSearch.clear();
      _nameSearchResults = [];
    });
    await _loadPreferredIds();
    await _loadNearby();
  }

  Future<void> _searchByName(String query) async {
    if (query.trim().length < 2) {
      setState(() => _nameSearchResults = []);
      return;
    }
    setState(() => _searchingByName = true);
    try {
      final api = context.read<AuthProvider>().api;
      final results = await api.searchProviders(query.trim());
      if (mounted) setState(() => _nameSearchResults = results);
    } finally {
      if (mounted) setState(() => _searchingByName = false);
    }
  }

  Future<void> _loadNearby() async {
    if (_specialty == null) return;
    setState(() => _locationStatus = _LocationStatus.loading);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _locationStatus = _LocationStatus.serviceOff);
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() => _locationStatus = _LocationStatus.denied);
        return;
      }
      final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium));
      if (!mounted) return;
      final api = context.read<AuthProvider>().api;
      final results = await api.getNearbyProviders(specialty: _specialty!, lat: position.latitude, lng: position.longitude);
      if (!mounted) return;
      setState(() {
        _nearby = results;
        _locationStatus = _LocationStatus.ready;
      });
    } catch (_) {
      if (mounted) setState(() => _locationStatus = _LocationStatus.error);
    }
  }

  Future<void> _togglePreferred(Map<String, dynamic> provider) async {
    final api = context.read<AuthProvider>().api;
    final id = provider['id'] as String;
    if (_preferredProviderIds.contains(id)) {
      await api.removePreferredProvider(_memberId!, id);
    } else {
      await api.addPreferredProvider(_memberId!, id);
    }
    await _loadPreferredIds();
  }

  void _selectProvider(Map<String, dynamic> provider) {
    setState(() {
      _selectedProviderId = provider['id'] as String;
      _selectedProvider = provider;
    });
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)), initialDate: DateTime.now());
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;
    setState(() => _datetime = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _book() async {
    if (_selectedProviderId == null || _datetime == null || _memberId == null) return;
    setState(() => _booking = true);
    try {
      final api = context.read<AuthProvider>().api;
      await api.bookAppointment({
        'member_id': _memberId,
        'provider_id': _selectedProviderId,
        'datetime': _datetime!.toIso8601String(),
        'sharing_preference': _sharingPreference,
        'reason_for_visit': _reasonForVisit.text.trim().isEmpty ? null : _reasonForVisit.text.trim(),
      });
      setState(() {
        _selectedProviderId = null;
        _selectedProvider = null;
        _specialty = null;
        _nearby = [];
        _preferredForSpecialty = [];
        _datetime = null;
        _reasonForVisit.clear();
      });
      await _load();
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  Future<void> _respond(String id, bool approve) async {
    await context.read<AuthProvider>().api.respondConsent(id, approve);
    _load();
  }

  Future<void> _editAppointment(Map<String, dynamic> appt) async {
    final reason = TextEditingController(text: appt['reason_for_visit'] as String? ?? '');
    DateTime datetime = DateTime.parse(appt['datetime'] as String);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Reschedule appointment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('With ${appt['provider']?['name'] ?? ''}', style: const TextStyle(color: careloopMuted, fontSize: 13)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  final date = await showDatePicker(context: dialogContext, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)), initialDate: datetime);
                  if (date == null || !dialogContext.mounted) return;
                  final time = await showTimePicker(context: dialogContext, initialTime: TimeOfDay.fromDateTime(datetime));
                  if (time == null) return;
                  setDialogState(() => datetime = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                },
                child: Text(datetime.toString().substring(0, 16)),
              ),
              const SizedBox(height: 10),
              TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason for visit (optional)')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    await context.read<AuthProvider>().api.editAppointment(appt['id'] as String, {
      'datetime': datetime.toIso8601String(),
      'reason_for_visit': reason.text.trim().isEmpty ? null : reason.text.trim(),
    });
    _load();
  }

  Future<void> _cancelAppointment(Map<String, dynamic> appt) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel this appointment?'),
        content: Text('Your visit with ${appt['provider']?['name'] ?? 'the doctor'} will be cancelled.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: careloopDanger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel appointment'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<AuthProvider>().api.cancelAppointment(appt['id'] as String);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_appointments == null || _members == null) return const LoadingCenter();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, careloopFabClearance),
        children: [
          SectionCard(
            title: 'Book an appointment',
            icon: Icons.event_available_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _memberId,
                  decoration: const InputDecoration(labelText: 'For'),
                  items: [for (final m in _members!) DropdownMenuItem(value: m['id'] as String, child: Text(m['name']))],
                  onChanged: (v) async {
                    setState(() {
                      _memberId = v;
                      _specialty = null;
                      _selectedProviderId = null;
                      _selectedProvider = null;
                      _nearby = [];
                      _preferredForSpecialty = [];
                    });
                    await _loadPreferredIds();
                  },
                ),
                const SizedBox(height: 10),
                InkWell(
                  borderRadius: BorderRadius.circular(careloopRadiusMd),
                  onTap: _pickSpecialty,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Specialization', suffixIcon: Icon(Icons.search_rounded, size: 20)),
                    child: Text(_specialty ?? 'Search specializations…', style: TextStyle(color: _specialty == null ? careloopMutedDim : careloopTextPrimary)),
                  ),
                ),
                const SizedBox(height: 10),
                const _SubHeading('OR SEARCH BY DOCTOR NAME', icon: Icons.person_search_rounded),
                TextField(
                  controller: _nameSearch,
                  decoration: InputDecoration(
                    hintText: 'Type a doctor\'s name…',
                    suffixIcon: _searchingByName
                        ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                        : (_nameSearch.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: () {
                                  _nameSearch.clear();
                                  setState(() => _nameSearchResults = []);
                                },
                              )
                            : const Icon(Icons.search_rounded, size: 20)),
                  ),
                  onChanged: (v) {
                    setState(() {}); // refresh the clear-icon visibility
                    _searchByName(v);
                  },
                ),
                // The dropdown half of "text box as well as dropdown" — a plain tappable list
                // right under the field rather than a popup, so it works the same on every
                // platform this app runs on.
                if (_nameSearchResults.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 260),
                    decoration: BoxDecoration(color: careloopSurfaceRaised, borderRadius: BorderRadius.circular(careloopRadiusMd), border: Border.all(color: careloopBorder)),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _nameSearchResults.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final p = _nameSearchResults[i] as Map<String, dynamic>;
                        return ListTile(
                          dense: true,
                          title: Text(p['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text('${p['specialty'] ?? ''} · ${p['clinic_name'] ?? ''}${p['city'] != null ? ' · ${p['city']}' : ''}', style: const TextStyle(fontSize: 12)),
                          onTap: () {
                            _selectProvider(p);
                            setState(() {
                              _nameSearch.text = p['name'] ?? '';
                              _nameSearchResults = [];
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
                if (_specialty != null) ...[
                  const SizedBox(height: 16),
                  if (_preferredForSpecialty.isNotEmpty) ...[
                    const _SubHeading('YOUR PREFERRED DOCTORS', icon: Icons.star_rounded),
                    for (final p in _preferredForSpecialty.cast<Map<String, dynamic>>())
                      _DoctorCard(
                        provider: p,
                        isPreferred: true,
                        isSelected: p['id'] == _selectedProviderId,
                        onTap: () => _selectProvider(p),
                        onToggleStar: () => _togglePreferred(p),
                        showDistance: false,
                      ),
                    const SizedBox(height: 14),
                  ],
                  _SubHeading('${_specialty!.toUpperCase()}S NEAR YOU (WITHIN 20KM)', icon: Icons.location_on_rounded),
                  _buildNearbySection(),
                ],
                if (_selectedProvider != null) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),
                  Text('Booking with ${_selectedProvider!['name']}', style: const TextStyle(fontWeight: FontWeight.w700, color: careloopTextPrimary)),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _pickDateTime,
                    child: Text(_datetime == null ? 'Pick date & time' : _datetime.toString().substring(0, 16)),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _sharingPreference,
                    decoration: const InputDecoration(labelText: 'What to share (a hint only — real access still needs your live consent at check-in)'),
                    items: const [
                      DropdownMenuItem(value: 'summary_card', child: Text('Summary card')),
                      DropdownMenuItem(value: 'full_history', child: Text('Full history')),
                    ],
                    onChanged: (v) => setState(() => _sharingPreference = v ?? 'full_history'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _reasonForVisit,
                    decoration: const InputDecoration(labelText: 'Reason for visit (optional)', hintText: 'e.g. follow-up on blood pressure'),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton(
                    onPressed: _booking || _datetime == null ? null : _book,
                    child: Text(_booking ? 'Booking…' : 'Confirm booking'),
                  ),
                ],
              ],
            ),
          ),
          // Collapsible — no such pattern existed anywhere in the app before this; built fresh
          // (a plain InkWell header driving an AnimatedSize) rather than adapting an existing one.
          InkWell(
            borderRadius: BorderRadius.circular(careloopRadiusSm),
            onTap: () => setState(() => _appointmentsExpanded = !_appointmentsExpanded),
            child: Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 8),
              child: Row(children: [
                const Icon(Icons.calendar_month_rounded, size: 16, color: careloopAccent),
                const SizedBox(width: 8),
                Expanded(child: Text('Booked appointments', style: careloopSectionHeading())),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(color: careloopAccentLight, borderRadius: BorderRadius.circular(999)),
                  child: Text('${_appointments!.length}', style: const TextStyle(color: careloopAccent, fontWeight: FontWeight.w700, fontSize: 11.5)),
                ),
                AnimatedRotation(
                  turns: _appointmentsExpanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: const Icon(Icons.chevron_right_rounded, color: careloopTextPrimary),
                ),
              ]),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: !_appointmentsExpanded
                ? const SizedBox.shrink()
                : LedgerTable(
                    rows: _appointments!.isEmpty
                        ? [const LedgerRow(label: 'No appointments yet — book one above', trailing: SizedBox.shrink())]
                        : [
                            for (final a in _appointments!.cast<Map<String, dynamic>>())
                              LedgerRow(
                                label: '${a['member']?['name']} — ${a['provider']?['name']}',
                                sublabel: (a['datetime'] as String).substring(0, 16).replaceAll('T', ' '),
                                // The member's own list shows only scheduled/cancelled/completed —
                                // the full provider-side state machine (checked in, consent
                                // requested/granted, in consultation, ...) stays internal to the
                                // doctor console.
                                trailing: a['status'] == 'consent_requested'
                                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                                        TextButton(onPressed: () => _respond(a['id'], true), child: const Text('Approve')),
                                        TextButton(onPressed: () => _respond(a['id'], false), style: TextButton.styleFrom(foregroundColor: careloopDanger), child: const Text('Deny')),
                                      ])
                                    : a['status'] == 'scheduled'
                                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                                            StatusPill.forMemberAppointmentStatus(a['status']),
                                            PopupMenuButton<String>(
                                              icon: const Icon(Icons.more_vert_rounded, size: 18, color: careloopMuted),
                                              onSelected: (choice) {
                                                if (choice == 'edit') _editAppointment(a);
                                                if (choice == 'cancel') _cancelAppointment(a);
                                              },
                                              itemBuilder: (_) => const [
                                                PopupMenuItem(value: 'edit', child: Text('Reschedule')),
                                                PopupMenuItem(value: 'cancel', child: Text('Cancel')),
                                              ],
                                            ),
                                          ])
                                        : StatusPill.forMemberAppointmentStatus(a['status']),
                              ),
                          ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNearbySection() {
    switch (_locationStatus) {
      case _LocationStatus.loading:
        return const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator()));
      case _LocationStatus.denied:
        return InfoBanner('Location access was denied, so nearby results can\'t be shown. You can still book a preferred doctor above, or allow location access and try again.', info: false);
      case _LocationStatus.serviceOff:
        return const InfoBanner('Turn on location services to find nearby doctors.', info: false);
      case _LocationStatus.error:
        return InfoBanner('Could not get your location. Try again.', info: false);
      case _LocationStatus.idle:
        return const SizedBox.shrink();
      case _LocationStatus.ready:
        break;
    }
    final within = _nearby.cast<Map<String, dynamic>>().where((p) => p['within_radius'] == true).toList();
    final farther = _nearby.cast<Map<String, dynamic>>().where((p) => p['within_radius'] != true).take(3).toList();
    if (_nearby.isEmpty) {
      return const Text('No doctors of this specialization are on record yet.', style: TextStyle(color: careloopMuted, fontSize: 13));
    }
    if (within.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('None within 20km — here are the closest available.', style: TextStyle(color: careloopMuted, fontSize: 12.5))),
        for (final p in farther) _DoctorCard(provider: p, isPreferred: _preferredProviderIds.contains(p['id']), isSelected: p['id'] == _selectedProviderId, onTap: () => _selectProvider(p), onToggleStar: () => _togglePreferred(p)),
      ]);
    }
    return Column(children: [for (final p in within) _DoctorCard(provider: p, isPreferred: _preferredProviderIds.contains(p['id']), isSelected: p['id'] == _selectedProviderId, onTap: () => _selectProvider(p), onToggleStar: () => _togglePreferred(p))]);
  }
}

class _SubHeading extends StatelessWidget {
  final String text;
  final IconData icon;
  const _SubHeading(this.text, {required this.icon});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(icon, size: 13, color: careloopMuted),
        const SizedBox(width: 6),
        Text(text, style: careloopEyebrow()),
      ]),
    );
  }
}

class _DoctorCard extends StatelessWidget {
  final Map<String, dynamic> provider;
  final bool isPreferred;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onToggleStar;
  final bool showDistance;
  const _DoctorCard({
    required this.provider,
    required this.isPreferred,
    required this.isSelected,
    required this.onTap,
    required this.onToggleStar,
    this.showDistance = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(careloopRadiusMd),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? careloopPrimaryGlow : careloopSurfaceRaised,
          borderRadius: BorderRadius.circular(careloopRadiusMd),
          border: Border.all(color: isSelected ? careloopPrimary : careloopBorder, width: isSelected ? 1.6 : 1),
        ),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(provider['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, color: careloopTextPrimary, fontSize: 14.5)),
                const SizedBox(height: 3),
                Text('${provider['clinic_name'] ?? ''}${provider['city'] != null ? ' · ${provider['city']}' : ''}', style: const TextStyle(color: careloopMuted, fontSize: 12, fontWeight: FontWeight.w400)),
                if (provider['availability_note'] != null) Text(provider['availability_note'], style: const TextStyle(color: careloopMuted, fontSize: 11.5, fontWeight: FontWeight.w400)),
                if (showDistance && provider['distance_km'] != null) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.near_me_rounded, size: 12, color: careloopInfo),
                    const SizedBox(width: 3),
                    Text('${provider['distance_km']} km away', style: const TextStyle(color: careloopInfo, fontSize: 11.5, fontWeight: FontWeight.w400)),
                  ]),
                ],
              ],
            ),
          ),
          IconButton(
            icon: Icon(isPreferred ? Icons.star_rounded : Icons.star_border_rounded, color: isPreferred ? careloopWarning : careloopMuted),
            onPressed: onToggleStar,
            tooltip: isPreferred ? 'Remove from preferred doctors' : 'Save as a preferred doctor',
          ),
        ]),
      ),
    );
  }
}
