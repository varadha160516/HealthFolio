import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';
import '../theme.dart';
import 'application_status_screen.dart';
import 'provider_application_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController(text: 'dr.rao@example.com');
  final _password = TextEditingController(text: 'password123');
  bool _busy = false;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().login(_email.text.trim(), _password.text);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DocGradientScaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(gradient: LinearGradient(colors: docPrimaryGradient), shape: BoxShape.circle),
                child: const Icon(Icons.medical_services_rounded, color: Colors.white, size: 30),
              ),
              const SizedBox(height: 18),
              Text('ClinDesk', style: docPageTitle().copyWith(fontSize: 27)),
              const SizedBox(height: 4),
              const Text('Sign in with your clinic credentials', style: TextStyle(color: docMuted, fontSize: 13.5)),
              const SizedBox(height: 30),
              TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 12),
              TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: docDanger, fontSize: 12.5), textAlign: TextAlign.center),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(onPressed: _busy ? null : _login, child: Text(_busy ? 'Signing in…' : 'Sign in')),
              ),
              const SizedBox(height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProviderApplicationScreen())),
                  child: const Text('Apply to join'),
                ),
                Container(width: 1, height: 14, color: docBorder),
                TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ApplicationStatusScreen())),
                  child: const Text('Check application status'),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
