import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

class ChildAuthScreen extends StatefulWidget {
  const ChildAuthScreen({super.key});

  @override
  State<ChildAuthScreen> createState() => _ChildAuthScreenState();
}

class _ChildAuthScreenState extends State<ChildAuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  final _auth = AuthService();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_email.text.trim().isEmpty || _password.text.isEmpty) {
        throw Exception(
            'Enter the email address and password your parent gave you.');
      }
      await _auth.signIn(
        email: _email.text.trim(),
        password: _password.text,
        role: 'child',
      );
    } catch (error) {
      debugPrint('Child sign-in failed: $error');
      if (mounted) {
        setState(() =>
            _error = 'Unable to sign in. Check your details and try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Family Guard Child'),
      ),
      body: AmbientBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Image.asset(
                        'assets/branding/child-logo.png',
                        width: 72,
                        height: 72,
                        fit: BoxFit.contain,
                        semanticLabel: 'Family Guard child logo',
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Welcome back',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your parent must create your account first. Ask them for your email and password.',
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  border: OutlineInputBorder(),
                  prefixIcon: LiveIcon(Icons.email),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: LiveIcon(Icons.lock),
                ),
                onSubmitted: (_) => _loading ? null : _signIn(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading ? null : _signIn,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: AppLoadingIndicator(size: 20),
                      )
                    : const Text('Sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
