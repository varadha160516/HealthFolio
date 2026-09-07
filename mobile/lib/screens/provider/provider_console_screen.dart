import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../auth_provider.dart';
import '../../theme.dart';
import '../../utils/motion.dart';
import 'appointment_workspace_screen.dart';

class ProviderConsoleScreen extends StatefulWidget {
  const ProviderConsoleScreen({super.key});
  @override
  State<ProviderConsoleScreen> createState() => _ProviderConsoleScreenState();
}

class _ProviderConsoleScreenState extends State<ProviderConsoleScreen> {
  List<dynamic>? _appointments;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load()); // live status poll (Section 7.1/8.1 step 3)
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final appts = await api.getAppointments();
    if (mounted) setState(() => _appointments = appts);
  }

  Future<void> _checkIn(String id) async {
    await context.read<AuthProvider>().api.checkIn(id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_appointments == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text("Today's appointments", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_appointments!.isEmpty) const Text('No appointments yet.', style: TextStyle(color: careloopMuted)),
          for (final a in _appointments!)
            Card(
              child: ListTile(
                title: Text(a['member']?['name'] ?? ''),
                subtitle: Text(a['datetime'].toString().substring(0, 16).replaceAll('T', ' ')),
                trailing: SizedBox(
                  width: 140,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      StatusPill.forAppointmentStatus(a['status']),
                    ],
                  ),
                ),
                onTap: () => Navigator.push(context, pushRoute(AppointmentWorkspaceScreen(appointmentId: a['id']))).then((_) => _load()),
                leading: a['status'] == 'scheduled'
                    ? IconButton(icon: const Icon(Icons.login_rounded, color: careloopPrimary), tooltip: 'Check in', onPressed: () => _checkIn(a['id']))
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}
