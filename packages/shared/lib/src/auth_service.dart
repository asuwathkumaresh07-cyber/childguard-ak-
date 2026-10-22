import 'dart:async';

import 'config.dart';
import 'local_store.dart';
import 'models.dart';
import 'supabase_service.dart';

class AuthService {
  AuthService([LocalFamilyStore? store, SupabaseService? supabase])
      : _store = store ?? LocalFamilyStore.instance,
        _supabase = supabase ?? SupabaseService.instance;

  final LocalFamilyStore _store;
  final SupabaseService _supabase;
  static final _localController = StreamController<Profile?>.broadcast();

  bool get isUsingSupabase =>
      SupabaseConfig.isRealSupabaseConfigured && _supabase.isInitialized;

  bool get isSupabaseConfigured => SupabaseConfig.isRealSupabaseConfigured;

  Profile? get user => isUsingSupabase
      ? (_supabase.isSignedIn ? _cachedSupabaseProfile : null)
      : _store.session;

  bool get isSignedIn =>
      isUsingSupabase ? _supabase.isSignedIn : _store.isSignedIn;

  static Profile? _cachedSupabaseProfile;

  Stream<Profile?> get authStateChanges async* {
    if (isUsingSupabase) {
      if (_supabase.isSignedIn) {
        _cachedSupabaseProfile = await _supabase.fetchMyProfile();
        yield _cachedSupabaseProfile;
      } else {
        yield null;
      }

      await for (final state in _supabase.authStateChanges) {
        if (state.session != null) {
          _cachedSupabaseProfile =
              await _supabase.fetchMyProfile(state.session!.user.id);
          yield _cachedSupabaseProfile;
        } else {
          _cachedSupabaseProfile = null;
          yield null;
        }
      }
    } else {
      await _store.init();
      yield _store.session;
      yield* _localController.stream;
    }
  }

  Future<Profile> signUp({
    required String email,
    required String password,
    required String role,
    required String displayName,
  }) async {
    _ensureBackendAvailable();
    if (role != 'parent') {
      throw Exception(
          'Only parents can register. Ask a parent to create the child account.');
    }
    if (email.trim().isEmpty || password.isEmpty) {
      throw Exception('Enter an email address and password.');
    }

    if (isUsingSupabase) {
      final profile = await _supabase.signUp(
        email: email,
        password: password,
        displayName: displayName,
      );
      _cachedSupabaseProfile = _supabase.isSignedIn ? profile : null;
      return profile;
    }

    final profile = await _store.registerParent(
      email: email,
      password: password,
      displayName: displayName,
    );
    _localController.add(profile);
    return profile;
  }

  Future<Profile> signIn({
    required String email,
    required String password,
    String role = 'parent',
    String displayName = '',
  }) async {
    _ensureBackendAvailable();
    if (isUsingSupabase) {
      final profile = await _supabase.signIn(
        email: email,
        password: password,
        role: role,
        displayName: displayName,
      );
      _cachedSupabaseProfile = profile;
      return profile;
    }

    final profile = await _store.signIn(
      email: email,
      password: password,
      role: role,
      displayName: displayName,
    );
    _localController.add(profile);
    return profile;
  }

  Future<Profile> createChildAccount({
    required String email,
    required String password,
    required String displayName,
  }) async {
    _ensureBackendAvailable();
    if (!isSignedIn) {
      throw Exception(
          'Sign in to the Parent app before creating a child account.');
    }
    final parent = await ensureProfile();
    if (parent == null || !parent.isParent) {
      throw Exception('Only a parent account can create a child account.');
    }
    if (email.trim().isEmpty || password.isEmpty) {
      throw Exception('Enter the child email address and password.');
    }

    if (isUsingSupabase) {
      return _supabase.createChildAccount(
        email: email,
        password: password,
        displayName: displayName,
      );
    }
    return _store.createChildAccount(
      email: email,
      password: password,
      displayName: displayName,
    );
  }

  Future<void> signOut() async {
    if (isUsingSupabase) {
      await _supabase.signOut();
      _cachedSupabaseProfile = null;
      return;
    }

    await _store.signOut();
    _localController.add(null);
  }

  Future<void> verifyCurrentPassword(String password) async {
    if (password.isEmpty) {
      throw Exception('Enter your parent password to approve this request.');
    }
    if (isUsingSupabase) {
      await _supabase.verifyCurrentPassword(password);
      return;
    }
    await _store.verifyCurrentPassword(password);
  }

  Future<Profile?> ensureProfile() async {
    if (isUsingSupabase) {
      _cachedSupabaseProfile = await _supabase.fetchMyProfile();
      return _cachedSupabaseProfile;
    }
    return _store.ensureProfile();
  }

  void _ensureBackendAvailable() {
    if (isSupabaseConfigured && !_supabase.isInitialized) {
      final detail = _supabase.initializationError;
      throw Exception(
        detail == null
            ? 'Supabase is configured but not connected. Check your project settings and network.'
            : 'Could not connect to Supabase: $detail',
      );
    }
  }
}
