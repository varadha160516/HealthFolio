import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import '../widgets/hero_mark.dart';

/// Shown when a valid session is cached but the user opted in to biometric/PIN unlock — gates
/// re-entry to the app behind fingerprint/face/PIN auth without needing a fresh server login.
class BiometricLockScreen extends StatefulWidget {
  const BiometricLockScreen({super.key});
  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> {
  bool _busy = false;
  String? _error;
  int _pinResetKey = 0;
  // The session's login-time displayName goes stale the moment Self's name is edited in the
  // Profile tab (same bug fixed on the Family dashboard earlier) — fetch the live Self member
  // name instead, falling back to the session name until that loads (or if it fails).
  String? _liveSelfName;

  @override
  void initState() {
    super.initState();
    // Deliberately does NOT auto-fire Face ID on arrival — the screen always lands on the PIN
    // entry first, so a returning user isn't interrupted by the native biometric prompt every
    // time. Face ID is still available as a manual tap below when it's enabled.
    _loadSelfName();
  }

  Future<void> _loadSelfName() async {
    try {
      final api = context.read<AuthProvider>().api;
      final f = await api.getFamily();
      final members = (f['members'] as List<dynamic>).cast<Map<String, dynamic>>();
      final selfMatches = members.where((m) => m['relationship_to_primary'] == 'self');
      if (mounted && selfMatches.isNotEmpty) setState(() => _liveSelfName = selfMatches.first['name'] as String?);
    } catch (_) {
      // Silent — the session displayName fallback covers this fine.
    }
  }

  Future<void> _attempt() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    final ok = await auth.unlockWithBiometrics();
    if (mounted) {
      setState(() {
        _busy = false;
        if (!ok) _error = auth.biometricError ?? "Didn't match — try again, or log out below to sign in with your password instead.";
      });
    }
  }

  void _submitPin(String pin) {
    final auth = context.read<AuthProvider>();
    final ok = auth.unlockWithPin(pin);
    if (!ok) {
      // Bumping the key remounts _PinBoxes, which clears its internal controller — simpler than
      // threading a "clear" callback down into it.
      setState(() {
        _error = 'Incorrect PIN — try again.';
        _pinResetKey++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final name = _liveSelfName ?? auth.session?.displayName;
    final showBiometric = auth.biometricEnabled && auth.biometricAvailable;
    final showPin = auth.pinEnabled;
    return GlassScaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: DecorativeBackdrop()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const HeroMark(size: 56),
                      const SizedBox(height: 14),
                      Text('Welcome back,', style: careloopSectionHeading().copyWith(fontSize: 17)),
                      Text('${name ?? 'there'}!', style: careloopPageTitle().copyWith(fontSize: 22)),
                      const SizedBox(height: 8),
                      const Text('"A smarter view of your health."',
                          style: TextStyle(color: careloopMuted, fontSize: 12.5, fontWeight: FontWeight.w400, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
                      const SizedBox(height: 10),
                      const Text('Please verify to continue.', style: TextStyle(color: careloopMuted, fontSize: 11.5)),
                      const SizedBox(height: 22),
                  if (_error != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(color: careloopAbnormalBg, borderRadius: BorderRadius.circular(careloopRadiusSm)),
                      child: Text(_error!, style: const TextStyle(color: careloopDanger), textAlign: TextAlign.center),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Face ID / fingerprint — the real biometric attempt (unchanged), just restyled
                  // as the reference's prominent tappable row instead of a plain button. Only
                  // shown when biometric unlock is actually the active method.
                  if (showBiometric) ...[
                    InkWell(
                      onTap: _busy ? null : _attempt,
                      borderRadius: BorderRadius.circular(careloopRadiusMd),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                        decoration: BoxDecoration(color: careloopSuccessBg, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder),
                        child: Row(children: [
                          const Icon(Icons.fingerprint_rounded, size: 26, color: careloopSuccess),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(_busy ? 'Checking…' : 'Unlock with Face ID', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: careloopTextPrimary)),
                              const Text('Fast & secure', style: TextStyle(color: careloopSuccess, fontSize: 11)),
                            ]),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: careloopSuccess),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // PIN — the real fallback: only shown once the user has actually set one (see
                  // the account menu's "Set PIN unlock"). Shown alone, with no Face ID row above,
                  // when biometrics aren't enabled/available on this device.
                  if (showPin) ...[
                    if (showBiometric) ...[
                      Row(children: [
                        const Expanded(child: Divider(color: careloopBorder)),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('or', style: TextStyle(color: careloopMutedDim, fontSize: 12))),
                        const Expanded(child: Divider(color: careloopBorder)),
                      ]),
                      const SizedBox(height: 16),
                    ],
                    Text('ENTER 6-DIGIT PIN', style: careloopEyebrow()),
                    const SizedBox(height: 8),
                    _PinBoxes(key: ValueKey(_pinResetKey), onSubmit: _submitPin),
                    const SizedBox(height: 18),
                  ],
                  InkWell(
                    onTap: () => context.read<AuthProvider>().logout(),
                    borderRadius: BorderRadius.circular(careloopRadiusMd),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                      decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder),
                      child: Row(children: [
                        const Icon(Icons.people_alt_rounded, size: 20, color: careloopPrimary),
                        const SizedBox(width: 12),
                        const Expanded(child: Text('Use another account', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: careloopTextPrimary))),
                        const Icon(Icons.chevron_right_rounded, color: careloopMuted),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.verified_user_rounded, size: 14, color: careloopSuccess),
                    const SizedBox(width: 6),
                    Text('Your data is encrypted and secure.', style: TextStyle(color: careloopMutedDim, fontSize: 10.5)),
                  ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Six digit-boxes over an invisible text field — auto-submits once all six are filled. A single
/// hidden field driving the visual boxes is much simpler than six separately-focused fields and
/// gives the same result: type-anywhere-in-the-row behavior with a real, working keyboard.
class _PinBoxes extends StatefulWidget {
  final ValueChanged<String> onSubmit;
  const _PinBoxes({super.key, required this.onSubmit});
  @override
  State<_PinBoxes> createState() => _PinBoxesState();
}

class _PinBoxesState extends State<_PinBoxes> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _focus.requestFocus(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (i) {
              final filled = i < _controller.text.length;
              return Container(
                width: 42,
                height: 48,
                decoration: BoxDecoration(color: careloopAccentLight, borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.center,
                child: filled ? Container(width: 8, height: 8, decoration: const BoxDecoration(color: careloopPrimary, shape: BoxShape.circle)) : null,
              );
            }),
          ),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                keyboardType: TextInputType.number,
                maxLength: 6,
                showCursor: false,
                decoration: const InputDecoration(counterText: '', border: InputBorder.none),
                onChanged: (v) {
                  final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
                  if (digits != v) {
                    _controller.value = TextEditingValue(text: digits, selection: TextSelection.collapsed(offset: digits.length));
                  }
                  setState(() {});
                  if (digits.length == 6) widget.onSubmit(digits);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
