import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import 'login_screen.dart';

/// Shown right after a provider application is submitted. The reference code is the applicant's
/// only way to check status or resubmit later — there's no email service in this app to send it
/// to them, so it has to land clearly here, with an easy way to copy it.
class ApplicationSubmittedScreen extends StatelessWidget {
  final String referenceCode;
  final String email;
  const ApplicationSubmittedScreen({super.key, required this.referenceCode, required this.email});

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
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 30),
              ),
              const SizedBox(height: 20),
              Text('Application submitted', style: docPageTitle().copyWith(fontSize: 24), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('Our team will review your details within 1–2 business days.', style: const TextStyle(color: docMuted, fontSize: 13.5, height: 1.4), textAlign: TextAlign.center),
              const SizedBox(height: 28),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: docSurface, borderRadius: BorderRadius.circular(docRadiusLg), border: docCardBorder, boxShadow: docCardShadow),
                child: Column(children: [
                  const Text('YOUR REFERENCE CODE', style: TextStyle(fontSize: 10, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  Text(referenceCode, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: docAccentDark, letterSpacing: 1.5)),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy_rounded, size: 15),
                    label: const Text('Copy code'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: referenceCode));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                    },
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              Text('Save this code along with the email you applied with ($email) — you\'ll need both to check your status.', style: const TextStyle(color: docMuted, fontSize: 12, height: 1.4), textAlign: TextAlign.center),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false),
                  child: const Text('Back to sign in'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
