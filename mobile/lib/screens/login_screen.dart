import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import '../widgets/hero_mark.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController(text: 'priya@example.com');
  final _password = TextEditingController(text: 'password123');
  bool _busy = false;
  String? _error;
  bool _obscure = true;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Deliberately just login and stop — login() calls notifyListeners(), which schedules
      // AuthGate to swap this whole screen out for HomeShell. Trying to show a dialog from here
      // right after (as this used to) races that swap: the dialog can end up attached to a
      // LoginScreen route that's being torn down underneath it, which is what caused the
      // "stuck after tapping Enable" bug. The biometric opt-in prompt now fires from HomeShell
      // instead, once things have actually settled — see main.dart.
      await context.read<AuthProvider>().login(_email.text.trim(), _password.text);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 6),
                      // Everything on this screen was tightened from its original spacing (badge,
                      // gaps, demo-account list) so the whole login flow fits one screen on a
                      // typical phone height without a scroll cutting a card off mid-row.
                      const Center(child: HeroMark()),
                      const SizedBox(height: 12),
                  Center(child: Text('HealthFolio', style: careloopPageTitle().copyWith(fontSize: 32, fontWeight: FontWeight.w700))),
                  const SizedBox(height: 5),
                  // The opening-screen quote, per the brief — replaces the previous plain tagline
                  // rather than sitting alongside it, so this already-compacted screen (see the
                  // scroll-cutoff fix earlier in this app's history) doesn't grow any taller.
                  Center(
                    child: Text('"A smarter view of your health."',
                        style: GoogleFonts.inter(color: careloopMuted, fontSize: 13, fontWeight: FontWeight.w400, fontStyle: FontStyle.italic)),
                  ),
                  const SizedBox(height: 18),
                  // Sign-in card — the first thing a user sees, so it gets the "hero" shape and
                  // elevation (extra-large radius, the stronger of the two shadow tokens) rather
                  // than the same flat treatment as an ordinary content card.
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: careloopSurface,
                      borderRadius: BorderRadius.circular(careloopRadiusXl),
                      border: careloopCardBorder,
                      boxShadow: careloopRaisedShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Welcome back', style: careloopSectionHeading()),
                        const SizedBox(height: 2),
                        const Text('Sign in to continue.', style: TextStyle(color: careloopMuted, fontSize: careloopTypeCaption)),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _email,
                          decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded, size: 20)),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _password,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                          obscureText: _obscure,
                          onSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: 14),
                        if (_error != null) ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: careloopAbnormalBg, borderRadius: BorderRadius.circular(careloopRadiusSm)),
                            child: Text(_error!, style: const TextStyle(color: careloopDanger, fontSize: 13)),
                          ),
                          const SizedBox(height: 10),
                        ],
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _busy ? null : _submit,
                            child: _busy
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                                : const Text('Sign in'),
                          ),
                        ),
                      ],
                    ),
                  ),
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
