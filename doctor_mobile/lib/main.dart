import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'api_client.dart';
import 'auth_provider.dart';
import 'theme.dart';
import 'screens/login_screen.dart';
import 'screens/home_shell.dart';

void main() {
  runApp(const DoctorConsoleApp());
}

class DoctorConsoleApp extends StatelessWidget {
  const DoctorConsoleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthProvider(ApiClient()),
      child: MaterialApp(
        title: 'Doctor Console',
        debugShowCheckedModeBanner: false,
        theme: docTheme(),
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
      return const DocGradientScaffold(body: LoadingCenter());
    }
    if (auth.restoreError) {
      return DocGradientScaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off_rounded, size: 44, color: docMuted),
              const SizedBox(height: 16),
              Text('Couldn\'t reach the server', style: docSectionHeading()),
              const SizedBox(height: 8),
              const Text('Check your connection and try again — your session is still saved.', style: TextStyle(color: docMuted), textAlign: TextAlign.center),
              const SizedBox(height: 22),
              ElevatedButton(onPressed: () => auth.retryRestore(), child: const Text('Retry')),
              const SizedBox(height: 10),
              TextButton(onPressed: () => auth.logout(), child: const Text('Log out and use password instead')),
            ]),
          ),
        ),
      );
    }
    if (!auth.isLoggedIn) return const LoginScreen();
    return const HomeShell();
  }
}
