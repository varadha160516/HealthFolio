import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api_client.dart';
import '../auth_provider.dart';
import '../theme.dart';
import '../widgets/glass.dart';

/// Creating a HealthFolio account. There is no open registration: you join with the one-time code a
/// clinic sent you on WhatsApp. If the clinic already registered you at the counter, the code links this
/// account to that record instead of starting an empty one.
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});
  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _accepted = false;
  bool _busy = false;
  String? _error;

  // Set once the code has been checked.
  String? _invitedBy;
  bool _claiming = false;

  ApiClient get _api => context.read<AuthProvider>().api;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _checkCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _api.checkInvite(_code.text.trim());
      if (!mounted) return;
      setState(() {
        _invitedBy = r['from'] as String?;
        _claiming = r['claims_existing_record'] == true;
        if (_name.text.isEmpty && r['name'] != null) _name.text = r['name'] as String;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _invitedBy = null;
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _canSubmit => !_busy && _invitedBy != null && _accepted && _email.text.trim().contains('@') && _password.text.length >= 8 && (_claiming || _name.text.trim().length >= 2);

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Signing up signs in — AuthGate swaps the whole app over on notifyListeners, so this screen just
      // has to get out of the way of the home screen underneath.
      await context.read<AuthProvider>().signUp(inviteCode: _code.text.trim(), name: _claiming ? null : _name.text.trim(), email: _email.text.trim(), password: _password.text);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final codeChecked = _invitedBy != null;
    return GlassScaffold(
      appBar: AppBar(title: const Text('Join HealthFolio')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusXl), border: careloopCardBorder, boxShadow: careloopRaisedShadow),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Enter your invite code', style: careloopSectionHeading()),
                  const SizedBox(height: 2),
                  const Text('Your clinic sent it to you on WhatsApp.', style: TextStyle(color: careloopMuted, fontSize: careloopTypeCaption)),
                  const SizedBox(height: 14),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: TextField(
                        controller: _code,
                        enabled: !codeChecked,
                        textCapitalization: TextCapitalization.characters,
                        autocorrect: false,
                        decoration: const InputDecoration(labelText: 'Invite code', hintText: 'ABCD-2345', prefixIcon: Icon(Icons.vpn_key_outlined, size: 20)),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _checkCode(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: codeChecked
                          ? IconButton(tooltip: 'Use a different code', icon: const Icon(Icons.edit_rounded, size: 18), onPressed: () => setState(() => _invitedBy = null))
                          : OutlinedButton(onPressed: _busy || _code.text.trim().length < 8 ? null : _checkCode, child: const Text('Check')),
                    ),
                  ]),
                  if (codeChecked) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: careloopSuccess.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(careloopRadiusSm)),
                      child: Row(children: [
                        const Icon(Icons.verified_rounded, size: 18, color: careloopSuccess),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _claiming ? 'Invited by $_invitedBy. Your visit record from the clinic will be waiting for you.' : 'Invited by $_invitedBy.',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    if (!_claiming) ...[
                      TextField(controller: _name, textCapitalization: TextCapitalization.words, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Your name', prefixIcon: Icon(Icons.person_outline_rounded, size: 20))),
                      const SizedBox(height: 10),
                    ],
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded, size: 20)),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _password,
                      obscureText: _obscure,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Choose a password',
                        helperText: 'At least 8 characters',
                        prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                        suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20), onPressed: () => setState(() => _obscure = !_obscure)),
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      value: _accepted,
                      onChanged: (v) => setState(() => _accepted = v ?? false),
                      title: const Text('I agree to join this pilot', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: const Text(
                        'HealthFolio stores your health records on our server and reads the reports you upload with AI. A doctor only sees your records for a visit if you approve it, and that access ends when the visit does.',
                        style: TextStyle(fontSize: 11.5, color: careloopMuted, height: 1.35),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: careloopAbnormalBg, borderRadius: BorderRadius.circular(careloopRadiusSm)),
                      child: Text(_error!, style: const TextStyle(color: careloopDanger, fontSize: 13)),
                    ),
                  ],
                  if (codeChecked) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _canSubmit ? _submit : null,
                        child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)) : const Text('Create my account'),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
