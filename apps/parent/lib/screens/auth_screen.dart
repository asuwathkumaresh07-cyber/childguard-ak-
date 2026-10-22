import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import '../widgets/user_error.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController(text: 'Parent');
  bool _isSignUp = true;
  bool _loading = false;
  String? _error;
  String? _message;

  final _auth = AuthService();

  String _friendlyAuthError(Object error) {
    final details = error.toString().toLowerCase();
    if (details.contains('invalid login credentials') ||
        details.contains('invalid_credentials') ||
        details.contains('wrong password')) {
      return 'Email or password is incorrect. Please try again.';
    }
    if (details.contains('email not confirmed') ||
        details.contains('email_not_confirmed') ||
        details.contains('confirm your email')) {
      return 'Please verify your email, then try signing in again.';
    }
    if (details.contains('already registered') ||
        details.contains('user_already_exists')) {
      return 'This email already has an account. Sign in instead.';
    }
    if (details.contains('weak password') ||
        details.contains('password should be')) {
      return 'Choose a stronger password and try again.';
    }
    if (details.contains('socketexception') ||
        details.contains('failed host lookup') ||
        details.contains('network is unreachable') ||
        details.contains('connection refused') ||
        details.contains('connection timed out')) {
      return 'Can’t connect right now. Check your internet and try again.';
    }
    return userFacingError;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
      _message = null;
    });
    try {
      if (_email.text.trim().isEmpty || _password.text.isEmpty) {
        throw Exception('Enter your email address and password.');
      }
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim())) {
        throw Exception('Enter a valid email address.');
      }
      if (_isSignUp) {
        final minimumPasswordLength = _auth.isUsingSupabase ? 6 : 4;
        if (_password.text.length < minimumPasswordLength) {
          throw Exception(
              'Use a password with at least $minimumPasswordLength characters.');
        }
        await _auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          role: 'parent',
          displayName: _name.text.trim().isEmpty ? 'Parent' : _name.text.trim(),
        );
        if (_auth.isUsingSupabase && !_auth.isSignedIn && mounted) {
          setState(() {
            _isSignUp = false;
            _message =
                'Account created. Check your email to confirm it, then sign in.';
          });
        }
      } else {
        await _auth.signIn(
          email: _email.text.trim(),
          password: _password.text,
          role: 'parent',
          displayName: _name.text.trim(),
        );
      }
    } catch (e) {
      if (mounted) {
        reportAppError('authenticate parent', e);
        setState(() => _error = _friendlyAuthError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Family Guard'),
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
                      LiveIcon(
                        Icons.shield_moon_outlined,
                        size: 38,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Parent portal',
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
              const SizedBox(height: 6),
              Text(
                'Sign in to manage your family. Child accounts are created from the parent dashboard.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              const SizedBox(height: 24),
              if (_isSignUp) ...[
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Your name',
                    border: OutlineInputBorder(),
                    prefixIcon: LiveIcon(Icons.person),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
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
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: LiveIcon(Icons.lock),
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(
                  _message!,
                  style: TextStyle(color: Colors.blue.shade800),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isSignUp
                        ? 'Create Parent Account'
                        : 'Sign in as Parent'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() {
                  _isSignUp = !_isSignUp;
                  _message = null;
                  _error = null;
                }),
                child: Text(
                  _isSignUp
                      ? 'Already have an account? Sign In'
                      : "Don't have an account? Create Account",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
