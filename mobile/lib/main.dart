import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'api_client.dart';
import 'auth_provider.dart';
import 'theme.dart';
import 'screens/login_screen.dart';
import 'screens/biometric_lock_screen.dart';
import 'screens/member/family_dashboard_screen.dart';
import 'screens/member/appointments_screen.dart';
import 'screens/member/ai_chat_screen.dart';
import 'screens/lab_tests/lab_tests_home_screen.dart';
import 'screens/provider/provider_console_screen.dart';
import 'screens/admin/admin_review_queue_screen.dart';
import 'screens/member/invoice_payment_dialog.dart';
import 'utils/motion.dart';
import 'widgets/glass.dart';
import 'widgets/gradient_fab.dart';

void main() {
  runApp(const CareLoopApp());
}

class CareLoopApp extends StatelessWidget {
  const CareLoopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthProvider(ApiClient()),
      child: MaterialApp(
        title: 'HealthFolio',
        debugShowCheckedModeBanner: false,
        theme: careloopTheme(),
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.loading) {
      return const GlassScaffold(body: Center(child: CircularProgressIndicator(color: careloopPrimary)));
    }
    // A cached token exists but couldn't be verified because the server/network was unreachable
    // — NOT proof the session is invalid, so this shows a retry rather than falling through to
    // LoginScreen and losing a perfectly good PIN/biometric-protected session over a hiccup.
    if (auth.restoreError) {
      return _RestoreErrorScreen(onRetry: () => auth.retryRestore());
    }
    if (auth.session == null) {
      return const LoginScreen();
    }
    if (auth.locked) {
      return const BiometricLockScreen();
    }
    return const HomeShell();
  }
}

class _RestoreErrorScreen extends StatelessWidget {
  final VoidCallback onRetry;
  const _RestoreErrorScreen({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 44, color: careloopMuted),
              const SizedBox(height: 16),
              Text('Couldn\'t reach HealthFolio', style: careloopSectionHeading()),
              const SizedBox(height: 8),
              const Text('Check your connection and try again — your session is still saved.', style: TextStyle(color: careloopMuted), textAlign: TextAlign.center),
              const SizedBox(height: 22),
              ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => context.read<AuthProvider>().logout(),
                child: const Text('Log out and use password instead'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Role-based top-level shell — the mobile equivalent of the web app's sidebar (Shell.tsx).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _memberTabIndex = 0;
  Timer? _consentPoll;
  bool _consentDialogOpen = false;
  Timer? _invoicePoll;
  bool _invoiceDialogOpen = false;
  final Set<String> _seenInvoiceIds = {};

  @override
  void initState() {
    super.initState();
    // Fires once, right after HomeShell has actually settled in — not from LoginScreen (see
    // login_screen.dart for why that raced the login->HomeShell transition and got stuck).
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOfferBiometricOptIn());
    if (context.read<AuthProvider>().session?.isMember == true) {
      _checkConsentRequests();
      _consentPoll = Timer.periodic(const Duration(seconds: 8), (_) => _checkConsentRequests());
      _checkPendingInvoices();
      _invoicePoll = Timer.periodic(const Duration(seconds: 8), (_) => _checkPendingInvoices());
    }
  }

  @override
  void dispose() {
    _consentPoll?.cancel();
    _invoicePoll?.cancel();
    super.dispose();
  }

  // Same polling pattern as consent requests -- surfaces a completed visit's invoice as a
  // payment popup regardless of which tab the member is on. "Pay later" (closing the dialog) is
  // remembered per invoice ID for this session so it doesn't nag again every 8 seconds; a fresh
  // app launch will offer it again since that set isn't persisted, which is fine -- an unpaid
  // invoice should stay visible eventually, just not relentlessly mid-session.
  Future<void> _checkPendingInvoices() async {
    if (_invoiceDialogOpen || !mounted) return;
    final auth = context.read<AuthProvider>();
    if (auth.session?.isMember != true) return;
    try {
      final invoices = await auth.api.getFamilyInvoices();
      if (!mounted) return;
      final pending = invoices
          .cast<Map<String, dynamic>>()
          .where((i) => i['status'] == 'pending' && !_seenInvoiceIds.contains(i['id']))
          .toList();
      if (pending.isEmpty) return;
      await _showInvoiceDialog(pending.first);
    } catch (_) {
      // silent -- a transient network hiccup shouldn't interrupt the user with an error dialog
    }
  }

  Future<void> _showInvoiceDialog(Map<String, dynamic> invoice) async {
    setState(() => _invoiceDialogOpen = true);
    _seenInvoiceIds.add(invoice['id'] as String);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => InvoicePaymentDialog(invoice: invoice),
    );
    if (mounted) setState(() => _invoiceDialogOpen = false);
  }

  // Polls for a doctor's live in-app consent request and surfaces it as a blocking dialog
  // regardless of which tab the member is on -- previously this only showed up if the member
  // happened to already be on the Appointments tab and pulled to refresh, so a request could
  // sit unanswered until it expired even though the app was open the whole time.
  Future<void> _checkConsentRequests() async {
    if (_consentDialogOpen || !mounted) return;
    final auth = context.read<AuthProvider>();
    if (auth.session?.isMember != true) return;
    try {
      final appts = await auth.api.getAppointments();
      if (!mounted) return;
      final pending = appts.cast<Map<String, dynamic>>().where((a) => a['status'] == 'consent_requested').toList();
      if (pending.isEmpty) return;
      await _showConsentDialog(pending.first);
    } catch (_) {
      // silent -- a transient network hiccup shouldn't interrupt the user with an error dialog
    }
  }

  Future<void> _showConsentDialog(Map<String, dynamic> appt) async {
    setState(() => _consentDialogOpen = true);
    final id = appt['id'] as String;
    final providerName = appt['provider']?['name'] as String? ?? 'Your doctor';
    final scope = appt['consentGrant']?['scope'] as String? ?? 'full history';
    final approve = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Consent request'),
        content: Text('$providerName is requesting $scope access for your current visit. Approve access?'),
        actions: [
          OutlinedButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Deny')),
          ElevatedButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Approve')),
        ],
      ),
    );
    if (approve != null && mounted) {
      try {
        await context.read<AuthProvider>().api.respondConsent(id, approve);
      } catch (_) {}
    }
    if (mounted) setState(() => _consentDialogOpen = false);
  }

  Future<void> _maybeOfferBiometricOptIn() async {
    final auth = context.read<AuthProvider>();
    if (!auth.justLoggedIn || !auth.biometricAvailable || auth.biometricEnabled) return;
    auth.clearJustLoggedIn();
    if (!mounted) return;
    final enable = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Use fingerprint or face unlock?'),
        content: const Text('Skip typing your password next time — unlock HealthFolio with your fingerprint or face instead.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Not now')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Enable')),
        ],
      ),
    );
    if (enable == true) await auth.setBiometricEnabled(true);
  }

  Future<void> _openChatPicker(BuildContext context) async {
    final api = context.read<AuthProvider>().api;
    final family = await api.getFamily();
    if (!context.mounted) return;
    final members = (family['members'] as List<dynamic>).cast<Map<String, dynamic>>();
    final chosen = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(careloopRadiusXl))),
      builder: (_) => _MemberPickerSheet(members: members),
    );
    if (chosen != null && context.mounted) {
      Navigator.push(context, pushRoute(AiChatScreen(member: chosen)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final session = auth.session!;

    if (session.isMember) {
      final pages = [const FamilyDashboardScreen(), const AppointmentsScreen(), const LabTestsHomeScreen()];
      return GlassScaffold(
        appBar: GlassAppBar(title: const _BrandTitle(), actions: const [_AccountMenuButton()]),
        body: pages[_memberTabIndex],
        bottomNavigationBar: GlassBottomBar(
          child: NavigationBar(
            selectedIndex: _memberTabIndex,
            onDestinationSelected: (i) => setState(() => _memberTabIndex = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.family_restroom_rounded), label: 'Family'),
              NavigationDestination(icon: Icon(Icons.event_rounded), label: 'Appointments'),
              NavigationDestination(icon: Icon(Icons.science_rounded), label: 'Lab Tests'),
            ],
          ),
        ),
        // Reachable before drilling into any specific member — picks who to ask about first,
        // since "Ask me" is inherently member-scoped (see MemberProfileScreen for the in-context
        // version of this same button, which skips the picker since the member is already known).
        // Extended (icon + visible label), not icon-only — the name should actually read on screen.
        floatingActionButton: GradientFab(
          tooltip: 'Ask me',
          label: 'Ask me',
          icon: Icons.chat_bubble_rounded,
          onPressed: () => _openChatPicker(context),
        ),
        fabStorageKey: 'home_ask_me',
      );
    }

    if (session.isProvider) {
      return GlassScaffold(
        appBar: GlassAppBar(title: const _BrandTitle(subtitle: 'Console'), actions: const [_AccountMenuButton()]),
        body: const ProviderConsoleScreen(),
      );
    }

    return GlassScaffold(
      appBar: GlassAppBar(title: const _BrandTitle(subtitle: 'Admin'), actions: const [_AccountMenuButton()]),
      body: const AdminReviewQueueScreen(),
    );
  }
}

/// The wordmark — a pink badge next to the name, sitting on the white app bar. The badge is
/// tinted (not plain white) now that the chrome itself is white too — a white-on-white badge
/// would have no contrast against it.
class _BrandTitle extends StatelessWidget {
  final String? subtitle;
  const _BrandTitle({this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: careloopBlush, borderRadius: BorderRadius.circular(11), border: Border.all(color: careloopPanelBorder)),
        child: const Icon(Icons.favorite_rounded, color: Color(0xFFD98F73), size: 17),
      ),
      const SizedBox(width: 10),
      Text('HealthFolio', style: careloopSectionHeading(color: careloopTextPrimary).copyWith(fontSize: 22)),
      if (subtitle != null) ...[
        const SizedBox(width: 6),
        Text(subtitle!, style: const TextStyle(color: careloopPanelLabel, fontWeight: FontWeight.w500, fontSize: 16)),
      ],
    ]);
  }
}

class _AccountMenuButton extends StatelessWidget {
  const _AccountMenuButton();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (choice) {
        // "Log out" re-locks to the PIN/Face ID screen when one is set up, rather than fully
        // signing out — see AuthProvider.lock(). "Use another account" on that lock screen is
        // still the real full sign-out.
        if (choice == 'logout') auth.lock();
        if (choice == 'biometric_off') auth.setBiometricEnabled(false);
        if (choice == 'pin_set') _showSetPinDialog(context, auth);
        if (choice == 'pin_off') auth.clearPin();
      },
      itemBuilder: (_) => [
        if (auth.biometricEnabled) const PopupMenuItem(value: 'biometric_off', child: Text('Turn off fingerprint/face unlock')),
        PopupMenuItem(value: 'pin_set', child: Text(auth.pinEnabled ? 'Change PIN' : 'Set PIN unlock')),
        if (auth.pinEnabled) const PopupMenuItem(value: 'pin_off', child: Text('Turn off PIN unlock')),
        const PopupMenuItem(value: 'logout', child: Text('Log out')),
      ],
    );
  }
}

Future<void> _showSetPinDialog(BuildContext context, AuthProvider auth) async {
  final pin = TextEditingController();
  final confirm = TextEditingController();
  String? error;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('Set a 6-digit PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Used to unlock HealthFolio on this device without fingerprint/face — e.g. when Face ID isn\'t set up or fails.', style: TextStyle(fontSize: 12.5)),
            const SizedBox(height: 14),
            TextField(
              controller: pin,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New PIN', counterText: ''),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: confirm,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm PIN', counterText: ''),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: const TextStyle(color: careloopDanger, fontSize: 12.5)),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (pin.text.length != 6 || !RegExp(r'^\d{6}$').hasMatch(pin.text)) {
                setState(() => error = 'PIN must be exactly 6 digits.');
                return;
              }
              if (pin.text != confirm.text) {
                setState(() => error = "PINs don't match.");
                return;
              }
              auth.setPin(pin.text);
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

/// "Who do you want to ask about?" — shown when AI Chat is opened from outside a specific
/// member's profile (the Family/Appointments shell), since the chat itself is always scoped to
/// one member.
class _MemberPickerSheet extends StatelessWidget {
  final List<Map<String, dynamic>> members;
  const _MemberPickerSheet({required this.members});

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ask me', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: careloopTextPrimary)),
            const SizedBox(height: 4),
            const Text('Choose who this question is about.', style: TextStyle(color: careloopMuted, fontSize: 13)),
            const SizedBox(height: 16),
            for (final m in members)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(color: careloopPrimaryGlow, shape: BoxShape.circle),
                  child: Center(child: Text(_initials(m['name'] ?? '?'), style: const TextStyle(color: careloopPrimary, fontWeight: FontWeight.w600, fontSize: 14))),
                ),
                title: Text(m['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, color: careloopTextPrimary)),
                onTap: () => Navigator.pop(context, m),
              ),
          ],
        ),
      ),
    );
  }
}
