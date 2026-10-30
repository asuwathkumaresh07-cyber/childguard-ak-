import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'categories.dart';
import 'config.dart';
import 'models.dart';

/// Full Supabase Backend Service for Family Guard.
/// Interacts directly with Supabase Auth, PostgreSQL database, and Realtime.
class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  bool _initialized = false;
  bool get isInitialized => _initialized;
  String? _initializedUrl;
  String? _initializedKey;
  String? _initializationError;
  String? get initializationError => _initializationError;

  SupabaseClient? get client {
    if (!_initialized) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Initialize Supabase if real credentials are provided
  Future<bool> init() async {
    await SupabaseConfig.init();

    if (!SupabaseConfig.isRealSupabaseConfigured) {
      _initialized = false;
      _initializedUrl = null;
      _initializedKey = null;
      _initializationError = null;
      return false;
    }

    try {
      final url = SupabaseConfig.url;
      final key = SupabaseConfig.anonKey;
      if (_initialized && _initializedUrl == url && _initializedKey == key) {
        return true;
      }

      Supabase? current;
      try {
        current = Supabase.instance;
      } on AssertionError {
        current = null;
      }
      if (current != null && current.isInitialized) {
        await current.dispose();
      }

      await Supabase.initialize(
        url: url,
        publishableKey: key,
      );
      _initialized = true;
      _initializedUrl = url;
      _initializedKey = key;
      _initializationError = null;
      return true;
    } catch (e) {
      debugPrint('Supabase initialize error: $e');
      _initialized = false;
      _initializedUrl = null;
      _initializedKey = null;
      _initializationError = e.toString();
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  User? get currentAuthUser => client?.auth.currentUser;
  bool get isSignedIn => currentAuthUser != null;

  Stream<AuthState> get authStateChanges {
    final c = client;
    if (c == null) return const Stream.empty();
    return c.auth.onAuthStateChange;
  }

  Future<Profile> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected');

    final res = await c.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: SupabaseConfig.authCallbackUrl,
      data: {
        'display_name':
            displayName.trim().isEmpty ? 'Parent' : displayName.trim(),
      },
    );

    final user = res.user;
    if (user == null) {
      throw Exception('Failed to sign up: no user returned');
    }

    return Profile(
      id: user.id,
      role: 'parent',
      displayName: displayName.trim().isEmpty ? 'Parent' : displayName.trim(),
      email: user.email ?? email,
    );
  }

  Future<Profile> signIn({
    required String email,
    required String password,
    String role = 'parent',
    String displayName = '',
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected');

    final res = await c.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );

    final user = res.user;
    if (user == null) {
      throw Exception('Sign in failed: invalid credentials');
    }

    final profile = await fetchMyProfile(user.id);
    if (profile == null) {
      await c.auth.signOut();
      throw Exception(
        'Your account profile is missing. Ask the administrator to apply the Family Guard database schema.',
      );
    }
    if (profile.role != role) {
      await c.auth.signOut();
      throw Exception(
        profile.isParent
            ? 'This is a parent account. Sign in through the Parent app.'
            : 'This is a child account. Sign in through the Child app.',
      );
    }
    return profile;
  }

  Future<Profile> createChildAccount({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final c = client;
    if (c == null || currentAuthUser == null) {
      throw Exception(
          'Sign in to the Parent app before creating a child account.');
    }

    final response = await c.functions.invoke(
      'create-child-account',
      body: {
        'email': email.trim(),
        'password': password,
        'display_name': displayName.trim(),
      },
    );
    final data = response.data;
    if (data is! Map) {
      throw Exception('The server returned an invalid child account response.');
    }
    return Profile(
      id: data['id'].toString(),
      role: 'child',
      displayName: (data['display_name'] as String?) ?? displayName.trim(),
      email: (data['email'] as String?) ?? email.trim(),
    );
  }

  Future<void> signOut() async {
    final c = client;
    if (c == null) return;
    await c.auth.signOut();
  }

  Future<void> verifyCurrentPassword(String password) async {
    final c = client;
    final user = currentAuthUser;
    final email = user?.email;
    if (c == null || user == null || email == null) {
      throw Exception('Sign in before verifying your password.');
    }

    final result = await c.auth.signInWithPassword(
      email: email,
      password: password,
    );
    if (result.user?.id != user.id) {
      await c.auth.signOut();
      throw Exception('Reauthentication did not match the signed-in account.');
    }
  }

  Future<Profile?> fetchMyProfile([String? userId]) async {
    final c = client;
    final uid = userId ?? currentAuthUser?.id;
    if (c == null || uid == null) return null;

    try {
      final data =
          await c.from('profiles').select().eq('id', uid).maybeSingle();

      if (data == null) return null;
      return Profile.fromJson(data);
    } catch (e) {
      debugPrint('Error fetching profile: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Family & Members
  // ---------------------------------------------------------------------------

  Future<Family?> fetchMyFamily() async {
    final c = client;
    final uid = currentAuthUser?.id;
    if (c == null || uid == null) return null;

    try {
      // 1. Check if owner of a family
      final owned =
          await c.from('families').select().eq('owner_id', uid).maybeSingle();

      if (owned != null) {
        return Family.fromJson(owned);
      }

      // 2. Check if member of a family (child role)
      final member = await c
          .from('family_members')
          .select('family_id, families(*)')
          .eq('profile_id', uid)
          .maybeSingle();

      if (member != null && member['families'] != null) {
        return Family.fromJson(member['families'] as Map<String, dynamic>);
      }

      return null;
    } catch (e) {
      debugPrint('Error fetching family: $e');
      return null;
    }
  }

  Future<List<FamilyMember>> fetchChildren(String familyId) async {
    final c = client;
    if (c == null) return [];

    try {
      final list = await c
          .from('family_members')
          .select('id, family_id, profile_id, profiles(*)')
          .eq('family_id', familyId);

      return (list as List)
          .map((row) => FamilyMember.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error fetching children: $e');
      return [];
    }
  }

  Future<PairCodeResult> createPairCode({int minutes = 30}) async {
    final c = client;
    final uid = currentAuthUser?.id;
    if (c == null || uid == null) {
      throw Exception('Not signed in to Supabase');
    }

    try {
      // Call stored procedure in Supabase
      final res = await c.rpc(
        'create_pair_code',
        params: {'p_minutes': minutes},
      );

      if (res is List && res.isNotEmpty) {
        final row = res.first as Map<String, dynamic>;
        return PairCodeResult.fromJson(row);
      } else if (res is Map<String, dynamic>) {
        return PairCodeResult.fromJson(res);
      }
      throw Exception('Unexpected pair code response');
    } catch (e) {
      debugPrint(
          'RPC create_pair_code failed: $e, falling back to direct table insert');
      // Direct table fallback
      var family = await fetchMyFamily();
      if (family == null) {
        final newFamily = await c
            .from('families')
            .insert({'owner_id': uid, 'name': 'My Family'})
            .select()
            .single();
        family = Family.fromJson(newFamily);
      }

      final code = (100000 + (DateTime.now().millisecondsSinceEpoch % 900000))
          .toString();
      final expires = DateTime.now().toUtc().add(Duration(minutes: minutes));

      await c.from('pair_codes').insert({
        'family_id': family.id,
        'code': code,
        'created_by': uid,
        'expires_at': expires.toIso8601String(),
      });

      return PairCodeResult(
        code: code,
        expiresAt: expires,
        familyId: family.id,
      );
    }
  }

  Future<String> redeemPairCode(String code) async {
    final c = client;
    final uid = currentAuthUser?.id;
    if (c == null || uid == null) {
      throw Exception('Not signed in to Supabase');
    }

    try {
      final res = await c.rpc(
        'redeem_pair_code',
        params: {'p_code': code.trim().toUpperCase()},
      );
      return res.toString();
    } catch (e) {
      debugPrint('RPC redeem_pair_code failed: $e, attempting direct fallback');
      final cleaned = code.trim().toUpperCase();
      final row = await c
          .from('pair_codes')
          .select()
          .eq('code', cleaned)
          .isFilter('used_at', null)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .maybeSingle();

      if (row == null) {
        throw Exception('Invalid or expired pair code');
      }

      final familyId = row['family_id'] as String;

      await c.from('family_members').upsert({
        'family_id': familyId,
        'profile_id': uid,
      }, onConflict: 'family_id, profile_id');

      await c.from('pair_codes').update({
        'used_at': DateTime.now().toUtc().toIso8601String(),
        'used_by': uid,
      }).eq('id', row['id']);

      return familyId;
    }
  }

  Future<ProtectionControlCode> createProtectionControlCode({
    required String familyId,
    required String childId,
    required String requestedAction,
  }) async {
    final c = client;
    if (c == null || currentAuthUser == null) {
      throw Exception('Sign in to the Parent app before generating a code.');
    }
    if (requestedAction != 'enable' && requestedAction != 'disable') {
      throw ArgumentError.value(requestedAction, 'requestedAction');
    }

    final result = await c.rpc(
      'create_protection_control_code',
      params: {
        'p_family_id': familyId,
        'p_child_id': childId,
        'p_requested_action': requestedAction,
      },
    );
    if (result is List && result.isNotEmpty) {
      return ProtectionControlCode.fromJson(
        Map<String, dynamic>.from(result.first as Map),
      );
    }
    if (result is Map) {
      return ProtectionControlCode.fromJson(
        Map<String, dynamic>.from(result),
      );
    }
    throw Exception('The server returned an invalid protection code.');
  }

  Future<String> redeemProtectionControlCode({
    required String code,
    required String requestedAction,
  }) async {
    final c = client;
    if (c == null || currentAuthUser == null) {
      throw Exception('Sign in to the Child app before entering a code.');
    }
    if (requestedAction != 'enable' && requestedAction != 'disable') {
      throw ArgumentError.value(requestedAction, 'requestedAction');
    }

    final result = await c.rpc(
      'redeem_protection_control_code',
      params: {
        'p_code': code.trim().toUpperCase(),
        'p_requested_action': requestedAction,
      },
    );
    if (result == 'rate_limited') {
      throw Exception('Too many code attempts. Wait 15 minutes and try again.');
    }
    if (result == 'invalid') {
      throw Exception(
        'The code is invalid, expired, already used, or for a different action.',
      );
    }
    if (result is! String || result != requestedAction) {
      throw Exception('The protection code was not accepted.');
    }
    return result;
  }

  Future<ChildDeviceStatus?> fetchChildDeviceStatus(String childId) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    final row = await c
        .from('child_device_status')
        .select()
        .eq('child_id', childId)
        .maybeSingle();
    if (row == null) return null;
    return ChildDeviceStatus.fromJson(row);
  }

  Future<String> fetchChildProtectionMode({
    required String familyId,
    required String childId,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    final row = await c
        .from('child_protection_modes')
        .select('mode')
        .eq('family_id', familyId)
        .eq('child_id', childId)
        .maybeSingle();
    return row?['mode'] as String? ?? 'strict';
  }

  Future<void> setChildProtectionMode({
    required String familyId,
    required String childId,
    required String mode,
  }) async {
    if (mode != 'strict' && mode != 'friendly') {
      throw ArgumentError.value(mode, 'mode');
    }
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    await c.from('child_protection_modes').upsert({
      'family_id': familyId,
      'child_id': childId,
      'mode': mode,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'child_id');
  }

  Future<List<ChildTamperEvent>> fetchChildTamperEvents({
    required String familyId,
    required String childId,
    int limit = 20,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    final rows = await c
        .from('child_tamper_events')
        .select()
        .eq('family_id', familyId)
        .eq('child_id', childId)
        .order('occurred_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map(
          (row) => ChildTamperEvent.fromJson(row as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> reportChildDeviceStatus({
    required bool vpnEnabled,
    required bool usageAccessEnabled,
    required bool accessibilityEnabled,
    required bool locationSharingEnabled,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    final response = await c.rpc(
      'report_child_device_status',
      params: {
        'p_vpn_enabled': vpnEnabled,
        'p_usage_access_enabled': usageAccessEnabled,
        'p_accessibility_enabled': accessibilityEnabled,
        'p_location_sharing_enabled': locationSharingEnabled,
      },
    );
    if (response is! List) {
      throw Exception('The server returned an invalid device status response.');
    }

    for (final value in response) {
      if (value is! Map) {
        throw Exception('The server returned an invalid tamper event.');
      }
      final event = Map<String, dynamic>.from(value);
      await c.functions.invoke(
        'send-tamper-alert',
        body: {'event_id': event['event_id']},
      );
    }
  }

  Future<void> registerParentPushToken(String token) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    await c.rpc(
      'register_parent_push_token',
      params: {'p_token': token},
    );
  }

  Future<void> removeParentPushToken(String token) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    await c.rpc(
      'remove_parent_push_token',
      params: {'p_token': token},
    );
  }

  RealtimeChannel? subscribeToChildTamperEvents(
    String familyId,
    void Function(ChildTamperEvent event) onEvent,
  ) {
    final c = client;
    if (c == null) return null;
    return c
        .channel('public:child_tamper_events:$familyId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'child_tamper_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'family_id',
            value: familyId,
          ),
          callback: (payload) {
            final record = payload.newRecord;
            if (record.isNotEmpty) {
              onEvent(ChildTamperEvent.fromJson(record));
            }
          },
        )
        .subscribe();
  }

  RealtimeChannel? subscribeToZoneEvents(
    String familyId,
    void Function(ZoneEvent event) onEvent,
  ) {
    final c = client;
    if (c == null) return null;
    return c
        .channel(
            'zone-events-$familyId-${DateTime.now().microsecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'zone_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'family_id',
            value: familyId,
          ),
          callback: (payload) {
            onEvent(ZoneEvent.fromJson(payload.newRecord));
          },
        )
        .subscribe();
  }

  RealtimeChannel? subscribeToChildLocations(
    String childId,
    void Function(ChildLocation location) onLocation,
  ) {
    final c = client;
    if (c == null) return null;
    return c
        .channel(
          'child-locations-$childId-${DateTime.now().microsecondsSinceEpoch}',
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'child_locations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'child_id',
            value: childId,
          ),
          callback: (payload) {
            final record = payload.newRecord;
            if (record.isNotEmpty) {
              onLocation(ChildLocation.fromJson(record));
            }
          },
        )
        .subscribe();
  }

  // ---------------------------------------------------------------------------
  // Category-Based Filtering
  // ---------------------------------------------------------------------------

  Future<List<String>> fetchBlockedCategories(String familyId) async {
    final c = client;
    if (c == null) return [];

    try {
      final rows = await c
          .from('blocked_categories')
          .select('category')
          .eq('family_id', familyId);

      return (rows as List).map((r) => r['category'].toString()).toList();
    } catch (e) {
      debugPrint('Error fetching blocked categories: $e');
      return [];
    }
  }

  Future<void> toggleCategory({
    required String familyId,
    required BlockCategory category,
    required bool enabled,
  }) async {
    final c = client;
    final uid = currentAuthUser?.id;
    if (c == null || uid == null) throw Exception('Not signed in');

    if (enabled) {
      await c.from('blocked_categories').upsert({
        'family_id': familyId,
        'category': category.id,
        'created_by': uid,
      }, onConflict: 'family_id, category');
    } else {
      await c
          .from('blocked_categories')
          .delete()
          .eq('family_id', familyId)
          .eq('category', category.id);
    }
  }

  Future<void> setBlockedCategories({
    required String familyId,
    required List<String> categoryIds,
  }) async {
    final c = client;
    final uid = currentAuthUser?.id;
    if (c == null || uid == null) throw Exception('Not signed in');

    // Remove existing
    await c.from('blocked_categories').delete().eq('family_id', familyId);

    // Insert new
    if (categoryIds.isNotEmpty) {
      final rows = categoryIds
          .map((cat) => {
                'family_id': familyId,
                'category': cat,
                'created_by': uid,
              })
          .toList();
      await c.from('blocked_categories').insert(rows);
    }
  }

  // ---------------------------------------------------------------------------
  // Specific Domain Filtering
  // ---------------------------------------------------------------------------

  Future<List<BlockListEntry>> fetchBlockList(String familyId) async {
    final c = client;
    if (c == null) return [];

    try {
      final rows = await c
          .from('block_list')
          .select()
          .eq('family_id', familyId)
          .order('created_at', ascending: false);

      return (rows as List)
          .map((r) => BlockListEntry.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error fetching block list: $e');
      return [];
    }
  }

  Future<void> addBlockDomain(String familyId, String domain) async {
    final c = client;
    final uid = currentAuthUser?.id;
    if (c == null || uid == null) throw Exception('Not signed in');

    final cleaned = _normalizeDomain(domain);
    if (cleaned.isEmpty) throw Exception('Invalid domain');

    await c.from('block_list').upsert({
      'family_id': familyId,
      'domain': cleaned,
      'created_by': uid,
    }, onConflict: 'family_id, domain');
  }

  Future<void> removeBlockDomain(String entryId) async {
    final c = client;
    if (c == null) throw Exception('Not connected');
    await c.from('block_list').delete().eq('id', entryId);
  }

  /// Combined list of custom blocked domains + all domains from active categories
  Future<List<String>> fetchEffectiveBlockedDomains(String familyId) async {
    final customEntries = await fetchBlockList(familyId);
    final categoryStrings = await fetchBlockedCategories(familyId);

    final cats =
        categoryStrings.map(BlockCategoryX.fromId).whereType<BlockCategory>();

    final fromCategories = CategoryDomainLists.domainsFor(cats);
    final customDomains = customEntries.map((e) => e.domain.toLowerCase());

    return {...fromCategories, ...customDomains}.toList()..sort();
  }

  Future<List<String>> fetchChildBlockedDomainOverrides({
    required String familyId,
    required String childId,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    final domainRows = await c
        .from('child_blocked_domains')
        .select('domain')
        .eq('family_id', familyId)
        .eq('child_id', childId);
    final categoryRows = await c
        .from('child_blocked_categories')
        .select('category')
        .eq('family_id', familyId)
        .eq('child_id', childId);
    final categories = (categoryRows as List)
        .map((row) => BlockCategoryX.fromId(row['category'] as String))
        .whereType<BlockCategory>();
    return {
      ...CategoryDomainLists.domainsFor(categories),
      ...(domainRows as List).map(
        (row) => (row['domain'] as String).toLowerCase(),
      ),
    }.toList()
      ..sort();
  }

  Future<void> addChildBlockedDomain({
    required String familyId,
    required String childId,
    required String domain,
  }) async {
    final c = client;
    final uid = currentAuthUser?.id;
    if (c == null || uid == null) throw Exception('Not signed in.');
    final cleaned = _normalizeDomain(domain);
    if (cleaned.isEmpty) throw Exception('Invalid domain.');
    await c.from('child_blocked_domains').upsert({
      'family_id': familyId,
      'child_id': childId,
      'domain': cleaned,
      'created_by': uid,
    }, onConflict: 'family_id,child_id,domain');
  }

  Future<void> removeChildBlockedDomain({
    required String familyId,
    required String childId,
    required String domain,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    await c
        .from('child_blocked_domains')
        .delete()
        .eq('family_id', familyId)
        .eq('child_id', childId)
        .eq('domain', _normalizeDomain(domain));
  }

  // ---------------------------------------------------------------------------
  // App Blocking
  // ---------------------------------------------------------------------------

  Future<List<BlockedAppEntry>> fetchBlockedApps(String familyId) async {
    final c = client;
    if (c == null) return [];

    try {
      final rows = await c
          .from('blocked_apps')
          .select()
          .eq('family_id', familyId)
          .order('created_at', ascending: false);

      return (rows as List)
          .map((r) => BlockedAppEntry.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error fetching blocked apps: $e');
      return [];
    }
  }

  Future<List<String>> fetchBlockedAppPackages(String familyId) async {
    final apps = await fetchBlockedApps(familyId);
    return apps.map((a) => a.packageName).toList();
  }

  Future<List<String>> fetchChildBlockedAppPackages({
    required String familyId,
    required String childId,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    final rows = await c
        .from('child_blocked_apps')
        .select('package_name')
        .eq('family_id', familyId)
        .eq('child_id', childId);
    return (rows as List).map((row) => row['package_name'] as String).toList();
  }

  Future<void> addChildBlockedApp({
    required String familyId,
    required String childId,
    required String packageName,
    required String appLabel,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    final package = packageName.trim();
    if (package.isEmpty) throw Exception('Invalid package name.');
    await c.from('child_blocked_apps').upsert({
      'family_id': familyId,
      'child_id': childId,
      'package_name': package,
      'app_label': appLabel.trim().isEmpty ? package : appLabel.trim(),
    }, onConflict: 'family_id,child_id,package_name');
  }

  Future<void> removeChildBlockedApp({
    required String familyId,
    required String childId,
    required String packageName,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    await c
        .from('child_blocked_apps')
        .delete()
        .eq('family_id', familyId)
        .eq('child_id', childId)
        .eq('package_name', packageName);
  }

  Future<void> addBlockedApp({
    required String familyId,
    required String packageName,
    String appLabel = '',
  }) async {
    final c = client;
    if (c == null) throw Exception('Not connected');

    final pkg = packageName.trim();
    if (pkg.isEmpty) throw Exception('Invalid package name');

    await c.from('blocked_apps').upsert({
      'family_id': familyId,
      'package_name': pkg,
      'app_label': appLabel.trim().isEmpty ? pkg : appLabel.trim(),
    }, onConflict: 'family_id, package_name');
  }

  Future<void> removeBlockedApp(String entryId) async {
    final c = client;
    if (c == null) throw Exception('Not connected');
    await c.from('blocked_apps').delete().eq('id', entryId);
  }

  // ---------------------------------------------------------------------------
  // Child Network Activity Monitoring (Domain Logs)
  // ---------------------------------------------------------------------------

  Future<void> insertDomainLog({
    required String familyId,
    required String domain,
    required String action,
    String? id,
    String? childId,
    DateTime? occurredAt,
  }) async {
    final c = client;
    final uid = childId ?? currentAuthUser?.id;
    if (c == null) throw Exception('Supabase is not connected.');
    if (uid == null) {
      throw Exception('Sign in before recording network activity.');
    }

    final row = {
      if (id != null) 'id': id,
      'child_id': uid,
      'family_id': familyId,
      'domain': domain.trim().toLowerCase(),
      'action': action,
      'occurred_at': (occurredAt ?? DateTime.now()).toUtc().toIso8601String(),
    };
    try {
      await c.from('domain_logs').insert(row);
    } catch (_) {
      if (id == null) rethrow;
      final existing = await c
          .from('domain_logs')
          .select('id')
          .eq('id', id)
          .eq('child_id', uid)
          .eq('family_id', familyId)
          .maybeSingle();
      if (existing == null) rethrow;
    }
  }

  Future<List<DomainLog>> fetchDomainLogs({
    required String familyId,
    String? childId,
    int? limit = 100,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    const pageSize = 1000;
    final result = <DomainLog>[];
    var offset = 0;
    while (limit == null || result.length < limit) {
      final count = limit == null
          ? pageSize
          : (limit - result.length).clamp(1, pageSize).toInt();
      var query = c.from('domain_logs').select().eq('family_id', familyId);
      if (childId != null) query = query.eq('child_id', childId);
      final rows = await query
          .order('occurred_at', ascending: false)
          .range(offset, offset + count - 1);
      final page = (rows as List)
          .map((row) => DomainLog.fromJson(row as Map<String, dynamic>))
          .toList();
      result.addAll(page);
      if (page.length < count) break;
      offset += page.length;
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Child App Usage Logs
  // ---------------------------------------------------------------------------

  Future<void> insertAppUsageLog({
    required String familyId,
    required String packageName,
    required String appLabel,
    required DateTime startedAt,
    String? id,
    DateTime? endedAt,
    int? durationSeconds,
    String? childId,
  }) async {
    final c = client;
    final uid = childId ?? currentAuthUser?.id;
    if (c == null) throw Exception('Supabase is not connected.');
    if (uid == null) throw Exception('Sign in before recording app usage.');

    final row = {
      if (id != null) 'id': id,
      'child_id': uid,
      'family_id': familyId,
      'package_name': packageName,
      'app_label': appLabel,
      'started_at': startedAt.toUtc().toIso8601String(),
      'ended_at': endedAt?.toUtc().toIso8601String(),
      'duration_seconds': durationSeconds,
    };
    try {
      await c.from('app_usage_logs').insert(row);
    } catch (_) {
      if (id == null) rethrow;
      final existing = await c
          .from('app_usage_logs')
          .select('id')
          .eq('id', id)
          .eq('child_id', uid)
          .eq('family_id', familyId)
          .maybeSingle();
      if (existing == null) rethrow;
    }
  }

  Future<List<AppUsageLog>> fetchAppUsageLogs({
    required String familyId,
    String? childId,
    int? limit = 100,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    const pageSize = 1000;
    final result = <AppUsageLog>[];
    var offset = 0;
    while (limit == null || result.length < limit) {
      final count = limit == null
          ? pageSize
          : (limit - result.length).clamp(1, pageSize).toInt();
      var query = c.from('app_usage_logs').select().eq('family_id', familyId);
      if (childId != null) query = query.eq('child_id', childId);
      final rows = await query
          .order('started_at', ascending: false)
          .range(offset, offset + count - 1);
      final page = (rows as List)
          .map((row) => AppUsageLog.fromJson(row as Map<String, dynamic>))
          .toList();
      result.addAll(page);
      if (page.length < count) break;
      offset += page.length;
    }
    return result;
  }

  Future<List<AppTimeLimit>> fetchAppTimeLimits({
    required String familyId,
    required String childId,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');

    final rows = await c
        .from('app_time_limits')
        .select()
        .eq('family_id', familyId)
        .eq('child_id', childId)
        .order('app_label');
    return (rows as List)
        .map((row) => AppTimeLimit.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveAppTimeLimit({
    required String familyId,
    required String childId,
    required String packageName,
    required String appLabel,
    required int dailyLimitSeconds,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    if (dailyLimitSeconds <= 0) {
      throw ArgumentError.value(
        dailyLimitSeconds,
        'dailyLimitSeconds',
        'Must be greater than zero.',
      );
    }

    await c.from('app_time_limits').upsert(
      {
        'family_id': familyId,
        'child_id': childId,
        'package_name': packageName.trim(),
        'app_label': appLabel.trim(),
        'daily_limit_seconds': dailyLimitSeconds,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'child_id,package_name',
    );
  }

  Future<void> removeAppTimeLimit({
    required String familyId,
    required String id,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');

    await c
        .from('app_time_limits')
        .delete()
        .eq('family_id', familyId)
        .eq('id', id);
  }

  Future<List<ExtraTimeRequest>> fetchExtraTimeRequests({
    required String familyId,
    String? childId,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');

    var query =
        c.from('extra_time_requests').select().eq('family_id', familyId);
    if (childId != null) query = query.eq('child_id', childId);
    final rows = await query.order('requested_at', ascending: false);
    return (rows as List)
        .map((row) => ExtraTimeRequest.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<String> createExtraTimeRequest({
    required String familyId,
    required String childId,
    required String packageName,
    required String appLabel,
    required int requestedMinutes,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    if (requestedMinutes <= 0 || requestedMinutes > 120) {
      throw ArgumentError.value(
        requestedMinutes,
        'requestedMinutes',
        'Must be between 1 and 120.',
      );
    }
    if (currentAuthUser?.id != childId) {
      throw Exception('Only the signed-in child can request extra time.');
    }
    if (packageName.trim().isEmpty) throw ArgumentError('Choose an app.');
    final pending = await c
        .from('extra_time_requests')
        .select('id')
        .eq('family_id', familyId)
        .eq('child_id', childId)
        .eq('package_name', packageName.trim())
        .eq('status', 'pending')
        .limit(1);
    if (pending.isNotEmpty) {
      throw StateError(
          'A request for this app is already waiting for your parent.');
    }
    // Existing RLS only permits children to insert pending requests. Avoid the
    // legacy RPC, which could approve automatically from bonuses/autonomy.
    await c.from('extra_time_requests').insert({
      'family_id': familyId,
      'child_id': childId,
      'package_name': packageName.trim(),
      'app_label': appLabel.trim(),
      'requested_minutes': requestedMinutes,
      'status': 'pending',
    });
    return 'pending';
  }

  Future<List<ZoneEvent>> fetchZoneEvents({
    required String familyId,
    String? childId,
    int limit = 30,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    var query = c.from('zone_events').select().eq('family_id', familyId);
    if (childId != null) query = query.eq('child_id', childId);
    final rows =
        await query.order('occurred_at', ascending: false).limit(limit);
    return (rows as List)
        .map((row) => ZoneEvent.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> resolveExtraTimeRequest({
    required String familyId,
    required String id,
    required bool approve,
    int? grantedMinutes,
  }) async {
    final c = client;
    final uid = currentAuthUser?.id;
    if (c == null || uid == null) {
      throw Exception('Sign in to the Parent app before resolving requests.');
    }
    if (approve &&
        (grantedMinutes == null ||
            grantedMinutes <= 0 ||
            grantedMinutes > 120)) {
      throw ArgumentError.value(
        grantedMinutes,
        'grantedMinutes',
        'Approval requires a positive number of minutes.',
      );
    }

    final updated = await c
        .from('extra_time_requests')
        .update({
          'status': approve ? 'approved' : 'denied',
          'granted_minutes': approve ? grantedMinutes : null,
          'resolved_at': DateTime.now().toUtc().toIso8601String(),
          'resolved_by': uid,
        })
        .eq('family_id', familyId)
        .eq('id', id)
        .eq('status', 'pending')
        .select('id');
    if (updated.length != 1) {
      throw StateError(
          'This request was already reviewed or you do not have permission. Refresh the rewards page.');
    }
  }

  Future<List<VpnControlRequest>> fetchVpnControlRequests({
    required String familyId,
    String? childId,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');

    var query =
        c.from('vpn_control_requests').select().eq('family_id', familyId);
    if (childId != null) query = query.eq('child_id', childId);
    final rows = await query.order('requested_at', ascending: false);
    return (rows as List)
        .map((row) => VpnControlRequest.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> createVpnControlRequest({
    required String familyId,
    required String childId,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');

    await c.from('vpn_control_requests').insert({
      'family_id': familyId,
      'child_id': childId,
    });
  }

  Future<void> resolveVpnControlRequest({
    required String familyId,
    required String id,
    required bool approve,
  }) async {
    final c = client;
    final uid = currentAuthUser?.id;
    if (c == null || uid == null) {
      throw Exception('Sign in to the Parent app before resolving requests.');
    }

    await c
        .from('vpn_control_requests')
        .update({
          'status': approve ? 'approved' : 'denied',
          'resolved_at': DateTime.now().toUtc().toIso8601String(),
          'resolved_by': uid,
        })
        .eq('family_id', familyId)
        .eq('id', id)
        .eq('status', 'pending');
  }

  Future<void> markVpnControlRequestApplied({
    required String id,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');

    await c.rpc(
      'acknowledge_vpn_control_request',
      params: {'p_request_id': id},
    );
  }

  Future<ChildLocation?> fetchLatestChildLocation(String childId) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    final row = await c
        .from('child_locations')
        .select()
        .eq('child_id', childId)
        .order('recorded_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : ChildLocation.fromJson(row);
  }

  Future<List<ChildLocation>> fetchChildLocationHistory(
    String childId, {
    int limit = 48,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    final rows = await c
        .from('child_locations')
        .select()
        .eq('child_id', childId)
        .order('recorded_at', ascending: false)
        .limit(limit);
    return rows.map(ChildLocation.fromJson).toList();
  }

  Future<void> recordChildLocation({
    required String familyId,
    required String childId,
    required double latitude,
    required double longitude,
    double? accuracyMeters,
  }) async {
    final c = client;
    if (c == null || currentAuthUser?.id != childId) {
      throw Exception('Only the signed-in child can share this location.');
    }
    if (latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw ArgumentError('The location coordinates are invalid.');
    }
    await c.from('child_locations').insert({
      'family_id': familyId,
      'child_id': childId,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy_meters': accuracyMeters,
    });
  }

  Future<List<FamilyZone>> fetchFamilyZones(String familyId) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    final rows = await c
        .from('family_zones')
        .select()
        .eq('family_id', familyId)
        .order('name');
    return (rows as List)
        .map((row) => FamilyZone.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<FamilyZone> saveFamilyZone({
    required String familyId,
    String? id,
    required String name,
    required String zoneType,
    required double latitude,
    required double longitude,
    required int radiusMeters,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    final row = <String, dynamic>{
      if (id != null) 'id': id,
      'family_id': familyId,
      'name': name.trim(),
      'zone_type': zoneType,
      'latitude': latitude,
      'longitude': longitude,
      'radius_meters': radiusMeters,
    };
    final saved = id == null
        ? await c.from('family_zones').insert(row).select().single()
        : await c
            .from('family_zones')
            .update(row)
            .eq('id', id)
            .eq('family_id', familyId)
            .select()
            .single();
    return FamilyZone.fromJson(saved);
  }

  Future<void> removeFamilyZone(String familyId, String zoneId) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    await c
        .from('family_zones')
        .delete()
        .eq('family_id', familyId)
        .eq('id', zoneId);
  }

  Future<List<ZoneAppRule>> fetchZoneAppRules(String familyId) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    final rows =
        await c.from('zone_app_rules').select().eq('family_id', familyId);
    return (rows as List)
        .map((row) => ZoneAppRule.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveZoneAppRule({
    required String familyId,
    required String zoneId,
    required String packageName,
    required String appLabel,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    await c.from('zone_app_rules').upsert(
      {
        'family_id': familyId,
        'zone_id': zoneId,
        'package_name': packageName.trim(),
        'app_label': appLabel.trim(),
      },
      onConflict: 'zone_id,package_name',
    );
  }

  Future<void> removeZoneAppRule(String ruleId) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    await c.from('zone_app_rules').delete().eq('id', ruleId);
  }

  Future<String> recordZoneEvent({
    required String familyId,
    required String childId,
    required String zoneId,
    required String eventType,
    String? packageName,
  }) async {
    final c = client;
    if (c == null || currentAuthUser?.id != childId) {
      throw Exception('Only the signed-in child can report zone activity.');
    }
    if (!{'entered', 'exited', 'off_task_app'}.contains(eventType)) {
      throw ArgumentError.value(eventType, 'eventType');
    }
    final event = await c
        .from('zone_events')
        .insert({
          'family_id': familyId,
          'child_id': childId,
          'zone_id': zoneId,
          'event_type': eventType,
          'package_name': packageName,
        })
        .select('id')
        .single();
    return event['id'] as String;
  }

  Future<void> sendParentZoneAlert(String eventId) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    await c.functions.invoke(
      'send-tamper-alert',
      body: {
        'event_id': eventId,
        'alert_type': 'zone_event',
      },
    );
  }

  Future<List<ChildTask>> fetchChildTasks({
    required String familyId,
    String? childId,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    var query = c
        .from('child_tasks')
        .select('*, task_submissions(photo_path, note)')
        .eq('family_id', familyId);
    if (childId != null) query = query.eq('child_id', childId);
    final rows = await query.order('created_at', ascending: false);
    return (rows as List)
        .map((row) => ChildTask.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> createChildTask({
    required String familyId,
    required String childId,
    required String title,
    required String description,
    String taskType = 'task',
    DateTime? dueAt,
    int points = 10,
  }) async {
    final c = client;
    final uid = currentAuthUser?.id;
    if (c == null || uid == null) {
      throw Exception('Sign in to the Parent app before assigning a task.');
    }
    await c.from('child_tasks').insert({
      'family_id': familyId,
      'child_id': childId,
      'title': title.trim(),
      'description': description.trim(),
      'task_type': taskType,
      'due_at': dueAt?.toUtc().toIso8601String(),
      'points': points,
      'created_by': uid,
    });
  }

  Future<void> submitChildTask({
    required String taskId,
    required Uint8List photoBytes,
    required String note,
    String contentType = 'image/jpeg',
  }) async {
    final c = client;
    final uid = currentAuthUser?.id;
    if (c == null || uid == null) {
      throw Exception('Sign in to the Child app before submitting a task.');
    }
    if (photoBytes.isEmpty) throw ArgumentError('Choose a non-empty photo.');
    final path = '$uid/$taskId/${DateTime.now().microsecondsSinceEpoch}.jpg';
    final bucket = c.storage.from('task-proof');
    await bucket.uploadBinary(
      path,
      photoBytes,
      fileOptions: FileOptions(contentType: contentType),
    );
    try {
      await c.from('task_submissions').insert({
        'task_id': taskId,
        'child_id': uid,
        'photo_path': path,
        'note': note.trim(),
      });
    } catch (error, stackTrace) {
      try {
        await bucket.remove([path]);
      } catch (cleanupError, cleanupStackTrace) {
        debugPrint('Could not remove an unlinked task photo: $cleanupError');
        debugPrintStack(stackTrace: cleanupStackTrace);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<String> createTaskPhotoUrl(String path) {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    return c.storage.from('task-proof').createSignedUrl(path, 300);
  }

  Future<void> reviewChildTask({
    required String familyId,
    required String taskId,
    required bool approve,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    final row = await c
        .from('child_tasks')
        .update({'status': approve ? 'approved' : 'rejected'})
        .eq('family_id', familyId)
        .eq('id', taskId)
        .eq('status', 'submitted')
        .select('id')
        .maybeSingle();
    if (row == null) throw Exception('The task is no longer awaiting review.');
  }

  Future<List<ChildMoodCheckin>> fetchChildMoodCheckins({
    required String familyId,
    String? childId,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    var query =
        c.from('child_mood_checkins').select().eq('family_id', familyId);
    if (childId != null) query = query.eq('child_id', childId);
    final rows = await query.order('created_at', ascending: false).limit(30);
    return (rows as List)
        .map((row) => ChildMoodCheckin.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> createChildMoodCheckin({
    required String familyId,
    required String childId,
    required String mood,
    String note = '',
  }) async {
    final c = client;
    if (c == null || currentAuthUser?.id != childId) {
      throw Exception('Only the signed-in child can submit a mood check-in.');
    }
    if (!{'great', 'okay', 'low', 'stressed'}.contains(mood)) {
      throw ArgumentError.value(mood, 'mood');
    }
    await c.from('child_mood_checkins').insert({
      'family_id': familyId,
      'child_id': childId,
      'mood': mood,
      'note': note.trim(),
    });
  }

  Future<ChildWeeklyInsight?> fetchLatestChildWeeklyInsight(
    String childId,
  ) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    final row = await c
        .from('child_weekly_insights')
        .select()
        .eq('child_id', childId)
        .order('week_start', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : ChildWeeklyInsight.fromJson(row);
  }

  Future<ChildWeeklyInsight> generateChildWeeklyInsight({
    required String familyId,
    required String childId,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    final result = await c.rpc(
      'generate_child_weekly_insight',
      params: {
        'p_family_id': familyId,
        'p_child_id': childId,
      },
    );
    if (result is! Map<String, dynamic>) {
      throw Exception('Supabase returned an invalid weekly insight.');
    }
    return ChildWeeklyInsight.fromJson(result);
  }

  RealtimeChannel? subscribeToChildWeeklyInsights(
    String childId,
    void Function(ChildWeeklyInsight insight) onInsight,
  ) {
    final c = client;
    if (c == null) return null;
    return c
        .channel(
          'child-weekly-insights-$childId-${DateTime.now().microsecondsSinceEpoch}',
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'child_weekly_insights',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'child_id',
            value: childId,
          ),
          callback: (payload) {
            final record = payload.newRecord;
            if (record.isNotEmpty) {
              onInsight(ChildWeeklyInsight.fromJson(record));
            }
          },
        )
        .subscribe();
  }

  Future<ChildStreak?> fetchChildStreak(String childId) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    final row = await c
        .from('child_streaks')
        .select()
        .eq('child_id', childId)
        .maybeSingle();
    return row == null ? null : ChildStreak.fromJson(row);
  }

  Future<List<ChildTemporaryAppUnlock>> fetchActiveChildAppUnlocks(
    String childId,
  ) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    final rows = await c
        .from('child_temporary_app_unlocks')
        .select()
        .eq('child_id', childId)
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .order('expires_at');
    return (rows as List)
        .map((row) =>
            ChildTemporaryAppUnlock.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<ChildTemporaryAppUnlock> redeemChildTemporaryAppUnlock({
    required String familyId,
    required String packageName,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    final result = await c.rpc(
      'redeem_child_temporary_app_unlock',
      params: {
        'p_family_id': familyId,
        'p_package_name': packageName,
      },
    );
    if (result is! Map<String, dynamic>) {
      throw Exception('Supabase returned an invalid app unlock.');
    }
    return ChildTemporaryAppUnlock.fromJson(result);
  }

  Future<ChildAutonomySettings> fetchChildAutonomySettings({
    required String familyId,
    required String childId,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    final row = await c
        .from('child_autonomy_settings')
        .select()
        .eq('family_id', familyId)
        .eq('child_id', childId)
        .maybeSingle();
    return row == null
        ? ChildAutonomySettings(
            childId: childId,
            familyId: familyId,
            enabled: false,
            minTrustScore: 80,
            dailyExtraMinutesCap: 15,
          )
        : ChildAutonomySettings.fromJson(row);
  }

  Future<void> saveChildAutonomySettings({
    required String familyId,
    required String childId,
    required bool enabled,
    required int minTrustScore,
    required int dailyExtraMinutesCap,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    if (minTrustScore < 0 || minTrustScore > 100) {
      throw ArgumentError.value(minTrustScore, 'minTrustScore');
    }
    if (dailyExtraMinutesCap < 1 || dailyExtraMinutesCap > 120) {
      throw ArgumentError.value(
        dailyExtraMinutesCap,
        'dailyExtraMinutesCap',
      );
    }
    await c.from('child_autonomy_settings').upsert(
      {
        'family_id': familyId,
        'child_id': childId,
        'enabled': enabled,
        'min_trust_score': minTrustScore,
        'daily_extra_minutes_cap': dailyExtraMinutesCap,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'child_id',
    );
  }

  Future<void> saveChildAppCategory({
    required String familyId,
    required String packageName,
    required String category,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    const allowed = {
      'educational',
      'creative',
      'social',
      'entertainment',
      'unproductive',
    };
    if (!allowed.contains(category)) {
      throw ArgumentError.value(category, 'category');
    }
    await c.from('child_app_categories').upsert(
      {
        'family_id': familyId,
        'package_name': packageName,
        'category': category,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'family_id,package_name',
    );
  }

  Future<Map<String, String>> fetchChildAppCategories(String familyId) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    final rows = await c
        .from('child_app_categories')
        .select('package_name, category')
        .eq('family_id', familyId);
    return {
      for (final row in rows as List)
        (row['package_name'] as String): (row['category'] as String),
    };
  }

  Future<Map<String, String>> fetchChildAppCategoryOverrides({
    required String familyId,
    required String childId,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    final rows = await c
        .from('child_app_category_overrides')
        .select('package_name, category')
        .eq('family_id', familyId)
        .eq('child_id', childId);
    return {
      for (final row in rows as List)
        row['package_name'] as String: row['category'] as String,
    };
  }

  Future<void> saveChildAppCategoryOverride({
    required String familyId,
    required String childId,
    required String packageName,
    required String category,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    const allowed = {
      'educational',
      'creative',
      'social',
      'entertainment',
      'unproductive',
    };
    if (!allowed.contains(category)) {
      throw ArgumentError.value(category, 'category');
    }
    await c.from('child_app_category_overrides').upsert({
      'family_id': familyId,
      'child_id': childId,
      'package_name': packageName,
      'category': category,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'family_id,child_id,package_name');
  }

  Future<List<String>> fetchChildBlockedCategories({
    required String familyId,
    required String childId,
  }) async {
    final c = client;
    if (c == null) throw Exception('Supabase is not connected.');
    final rows = await c
        .from('child_blocked_categories')
        .select('category')
        .eq('family_id', familyId)
        .eq('child_id', childId);
    return (rows as List).map((row) => row['category'] as String).toList();
  }

  Future<void> setChildBlockedCategories({
    required String familyId,
    required String childId,
    required List<String> categoryIds,
  }) async {
    final c = client;
    final uid = currentAuthUser?.id;
    if (c == null || uid == null) throw Exception('Not signed in.');
    final allowed = BlockCategory.values.map((category) => category.id).toSet();
    if (categoryIds.toSet().difference(allowed).isNotEmpty) {
      throw ArgumentError.value(categoryIds, 'categoryIds');
    }
    await c.rpc('set_child_blocked_categories', params: {
      'target_family_id': familyId,
      'target_child_id': childId,
      'category_ids': categoryIds.toSet().toList(),
    });
  }

  // ---------------------------------------------------------------------------
  // Realtime Subscriptions
  // ---------------------------------------------------------------------------

  /// Subscribes child to changes in block list and blocked categories
  RealtimeChannel? subscribeToBlockChanges(
    String familyId,
    void Function() onRulesChanged,
  ) {
    final c = client;
    if (c == null) return null;

    final channel = c.channel('public:family_rules:$familyId');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'block_list',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'family_id',
            value: familyId,
          ),
          callback: (_) => onRulesChanged(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'blocked_categories',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'family_id',
            value: familyId,
          ),
          callback: (_) => onRulesChanged(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'blocked_apps',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'family_id',
            value: familyId,
          ),
          callback: (_) => onRulesChanged(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'child_blocked_domains',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'family_id',
            value: familyId,
          ),
          callback: (_) => onRulesChanged(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'child_blocked_apps',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'family_id',
            value: familyId,
          ),
          callback: (_) => onRulesChanged(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'child_blocked_categories',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'family_id',
            value: familyId,
          ),
          callback: (_) => onRulesChanged(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'app_time_limits',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'family_id',
            value: familyId,
          ),
          callback: (_) => onRulesChanged(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'child_protection_modes',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'family_id',
            value: familyId,
          ),
          callback: (_) => onRulesChanged(),
        )
        .subscribe();

    return channel;
  }

  /// Subscribes parent to live domain network activity from children
  RealtimeChannel? subscribeToDomainLogs(
    String familyId,
    void Function(DomainLog log) onNewLog,
  ) {
    final c = client;
    if (c == null) return null;

    final channel = c.channel('public:domain_logs:$familyId');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'domain_logs',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'family_id',
            value: familyId,
          ),
          callback: (payload) {
            try {
              final newRecord = payload.newRecord;
              if (newRecord.isNotEmpty) {
                final log = DomainLog.fromJson(newRecord);
                onNewLog(log);
              }
            } catch (_) {}
          },
        )
        .subscribe();

    return channel;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _normalizeDomain(String input) {
    var d = input.trim().toLowerCase();
    d = d.replaceFirst(RegExp(r'^https?://'), '');
    d = d.split('/').first;
    d = d.split(':').first;
    if (d.startsWith('www.')) d = d.substring(4);
    return d;
  }
}
