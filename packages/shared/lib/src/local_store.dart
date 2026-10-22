import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'categories.dart';
import 'config.dart';
import 'models.dart';

/// Cross-app JSON store for same-device parent/child demo.
/// Prefers a public Documents path so both APKs can read/write the same file.
class LocalFamilyStore {
  LocalFamilyStore._();

  static final LocalFamilyStore instance = LocalFamilyStore._();

  static const _sessionKey = 'fg_session_profile_json';
  static const _uuid = Uuid();

  FamilyStoreSnapshot _data = const FamilyStoreSnapshot();
  Profile? _session;
  File? _file;
  bool _ready = false;

  Profile? get session => _session;
  bool get isSignedIn => _session != null;
  FamilyStoreSnapshot get snapshot => _data;

  Future<void> init() async {
    if (_ready) return;
    _file = await _resolveStoreFile();
    await _loadFromDisk();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    if (raw != null) {
      _session = Profile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
    _ready = true;
  }

  Future<File> _resolveStoreFile() async {
    final candidates = <Directory>[];

    if (Platform.isAndroid) {
      candidates.add(Directory('/storage/emulated/0/Documents/FamilyGuard'));
      candidates.add(Directory('/storage/emulated/0/Download/FamilyGuard'));
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          candidates.add(Directory(p.join(ext.path, 'FamilyGuardShared')));
        }
      } catch (_) {
        // Fall back to app-specific documents storage.
      }
    }
    final docs = await getApplicationDocumentsDirectory();
    candidates.add(Directory(p.join(docs.path, 'FamilyGuard')));

    for (final dir in candidates) {
      try {
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        final file = File(p.join(dir.path, 'family_data.json'));
        // Probe write access
        await file.writeAsString(
          await file.exists() ? await file.readAsString() : '{}',
          flush: true,
        );
        return file;
      } catch (_) {
        continue;
      }
    }

    final fallback = Directory(p.join(docs.path, 'FamilyGuard'));
    await fallback.create(recursive: true);
    return File(p.join(fallback.path, 'family_data.json'));
  }

  Future<void> _loadFromDisk() async {
    final file = _file;
    if (file == null || !await file.exists()) {
      _data = const FamilyStoreSnapshot(pairCode: DemoCredentials.pairCode);
      return;
    }
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty || raw.trim() == '{}') {
        _data = const FamilyStoreSnapshot(pairCode: DemoCredentials.pairCode);
        return;
      }
      _data = FamilyStoreSnapshot.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      _data = const FamilyStoreSnapshot(pairCode: DemoCredentials.pairCode);
    }
  }

  Future<void> reload() async {
    await _loadFromDisk();
  }

  Future<void> _persist() async {
    final file = _file;
    if (file == null) return;
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(_data.toJson()), flush: true);
  }

  Future<void> _saveSession(Profile? profile) async {
    _session = profile;
    final prefs = await SharedPreferences.getInstance();
    if (profile == null) {
      await prefs.remove(_sessionKey);
    } else {
      await prefs.setString(_sessionKey, jsonEncode(profile.toJson()));
    }
  }

  Future<Profile> registerParent({
    required String email,
    required String password,
    required String displayName,
  }) async {
    await init();
    final cleanedEmail = email.trim().toLowerCase();
    if (cleanedEmail.isEmpty || !cleanedEmail.contains('@')) {
      throw Exception('Enter a valid email address.');
    }
    if (password.length < 4) {
      throw Exception(
          'Password must be at least 4 characters in offline demo mode.');
    }
    if (_data.accounts.any((account) => account.email == cleanedEmail)) {
      throw Exception(
          'An account already exists for this email. Sign in instead.');
    }
    if (_data.accounts.any((account) => account.role == 'parent')) {
      throw Exception(
        'Offline demo mode supports one parent account. Sign in with the existing account.',
      );
    }

    final id = _uuid.v4();
    final name = displayName.trim().isEmpty ? 'Parent' : displayName.trim();
    final salt = _uuid.v4();
    final account = LocalAccount(
      id: id,
      role: 'parent',
      displayName: name,
      email: cleanedEmail,
      passwordSalt: salt,
      passwordHash: _hashPassword(salt, password),
    );
    final profile = Profile(
      id: id,
      role: 'parent',
      displayName: name,
      email: cleanedEmail,
    );
    final family = Family(
      id: 'family-${_uuid.v4()}',
      ownerId: id,
      name: 'My Family',
    );
    _data = _data.copyWith(
      family: family,
      accounts: [..._data.accounts, account],
      profiles: [..._data.profiles.where((item) => item.id != id), profile],
      pairCode: DemoCredentials.pairCode,
    );
    await _persist();
    await _saveSession(profile);
    return profile;
  }

  Future<Profile> createChildAccount({
    required String email,
    required String password,
    required String displayName,
  }) async {
    await init();
    final parent = _session;
    if (parent == null || !parent.isParent) {
      throw Exception('Only a signed-in parent can create a child account.');
    }
    final cleanedEmail = email.trim().toLowerCase();
    if (cleanedEmail.isEmpty || !cleanedEmail.contains('@')) {
      throw Exception('Enter a valid email address.');
    }
    if (password.length < 4) {
      throw Exception(
          'Password must be at least 4 characters in offline demo mode.');
    }
    if (_data.accounts.any((account) => account.email == cleanedEmail)) {
      throw Exception('An account already exists for this email.');
    }

    final id = _uuid.v4();
    final name = displayName.trim().isEmpty ? 'Child' : displayName.trim();
    final salt = _uuid.v4();
    final account = LocalAccount(
      id: id,
      role: 'child',
      displayName: name,
      email: cleanedEmail,
      passwordSalt: salt,
      passwordHash: _hashPassword(salt, password),
    );
    final profile = Profile(
      id: id,
      role: 'child',
      displayName: name,
      email: cleanedEmail,
    );
    final family = _data.family ??
        Family(
          id: 'family-${_uuid.v4()}',
          ownerId: parent.id,
          name: 'My Family',
        );
    final member = FamilyMember(
      id: 'member-$id',
      familyId: family.id,
      profileId: profile.id,
      profile: profile,
    );
    _data = _data.copyWith(
      family: family,
      accounts: [..._data.accounts, account],
      profiles: [..._data.profiles.where((item) => item.id != id), profile],
      members: [..._data.members.where((item) => item.profileId != id), member],
      pairCode: DemoCredentials.pairCode,
    );
    await _persist();
    return profile;
  }

  Future<Profile> signIn({
    required String email,
    required String password,
    required String role,
    String displayName = '',
  }) async {
    await init();
    final cleanedEmail = email.trim().toLowerCase();
    if (cleanedEmail.isEmpty || password.isEmpty) {
      throw Exception('Enter your email address and password.');
    }
    LocalAccount? account;
    for (final item in _data.accounts) {
      if (item.email == cleanedEmail) {
        account = item;
        break;
      }
    }
    if (account == null) {
      throw Exception(
        role == 'child'
            ? 'No child account was found. Ask your parent to create one.'
            : 'No parent account was found. Create a parent account first.',
      );
    }
    if (account.role != role) {
      throw Exception(
        account.role == 'parent'
            ? 'This is a parent account. Use the Parent app.'
            : 'This is a child account. Use the Child app.',
      );
    }
    if (_hashPassword(account.passwordSalt, password) != account.passwordHash) {
      throw Exception('Incorrect email or password.');
    }

    final profile = Profile(
      id: account.id,
      role: account.role,
      displayName: account.displayName,
      email: account.email,
    );
    await _saveSession(profile);
    return profile;
  }

  String _hashPassword(String salt, String password) =>
      sha256.convert(utf8.encode('$salt:$password')).toString();

  Future<void> signOut() async {
    await init();
    await _saveSession(null);
  }

  Future<Profile?> ensureProfile() async {
    await init();
    return _session;
  }

  Future<void> verifyCurrentPassword(String password) async {
    await init();
    final session = _session;
    if (session == null) {
      throw Exception('Sign in to the Parent app before approving requests.');
    }
    final account =
        _data.accounts.where((item) => item.id == session.id).firstOrNull;
    if (account == null ||
        _hashPassword(account.passwordSalt, password) != account.passwordHash) {
      throw Exception('Incorrect parent password.');
    }
  }

  Future<Profile?> fetchMyProfile() async {
    await init();
    return _session;
  }

  Future<Family?> fetchMyFamily() async {
    await init();
    await _loadFromDisk();
    final session = _session;
    if (session == null) return null;
    final family = _data.family;
    if (family == null) return null;
    if (session.isParent && family.ownerId == session.id) return family;
    final isMember = _data.members.any((m) => m.profileId == session.id);
    return isMember ? family : null;
  }

  Future<List<FamilyMember>> fetchChildren(String familyId) async {
    await init();
    await _loadFromDisk();
    return _data.members.where((m) => m.familyId == familyId).map((m) {
      Profile? profile;
      for (final p in _data.profiles) {
        if (p.id == m.profileId) {
          profile = p;
          break;
        }
      }
      return FamilyMember(
        id: m.id,
        familyId: m.familyId,
        profileId: m.profileId,
        profile: profile ?? m.profile,
      );
    }).toList();
  }

  Future<PairCodeResult> createPairCode({int minutes = 30}) async {
    await init();
    final session = _session;
    if (session == null || !session.isParent) {
      throw Exception('Only parents can create pair codes');
    }
    final family = _data.family ??
        Family(
          id: DemoCredentials.familyId,
          ownerId: session.id,
          name: 'My Family',
        );
    _data = _data.copyWith(
      family: family,
      pairCode: DemoCredentials.pairCode,
    );
    await _persist();
    return PairCodeResult(
      code: DemoCredentials.pairCode,
      expiresAt: DateTime.now().add(Duration(minutes: minutes)),
      familyId: family.id,
    );
  }

  Future<String> redeemPairCode(String code) async {
    await init();
    await _loadFromDisk();
    final session = _session;
    if (session == null || !session.isChild) {
      throw Exception('Only children can redeem pair codes');
    }
    final cleaned = code.trim().toUpperCase();
    if (cleaned != DemoCredentials.pairCode &&
        cleaned != _data.pairCode.toUpperCase()) {
      throw Exception('Invalid pair code. Use 1234 for demo.');
    }
    final family = _data.family ??
        Family(
          id: DemoCredentials.familyId,
          ownerId: DemoCredentials.parentId,
          name: 'My Family',
        );
    final member = FamilyMember(
      id: 'member-${session.id}',
      familyId: family.id,
      profileId: session.id,
      profile: session,
    );
    final members = [
      ..._data.members.where((m) => m.profileId != session.id),
      member,
    ];
    final profiles = [
      ..._data.profiles.where((p) => p.id != session.id),
      session,
    ];
    _data = _data.copyWith(
      family: family,
      members: members,
      profiles: profiles,
      pairCode: DemoCredentials.pairCode,
    );
    await _persist();
    return family.id;
  }

  Future<List<BlockListEntry>> fetchBlockList(String familyId) async {
    await init();
    await _loadFromDisk();
    return _data.blockList.where((e) => e.familyId == familyId).toList();
  }

  Future<List<String>> fetchBlockDomains(String familyId) async {
    final custom = await fetchBlockList(familyId);
    final cats = _data.blockedCategories
        .map(BlockCategoryX.fromId)
        .whereType<BlockCategory>();
    final fromCats = CategoryDomainLists.domainsFor(cats);
    return {...fromCats, ...custom.map((e) => e.domain.toLowerCase())}.toList()
      ..sort();
  }

  Future<List<String>> fetchBlockedCategories() async {
    await init();
    await _loadFromDisk();
    return List<String>.from(_data.blockedCategories);
  }

  Future<void> setBlockedCategories(List<String> categoryIds) async {
    await init();
    _data = _data.copyWith(blockedCategories: categoryIds);
    await _persist();
  }

  Future<void> toggleCategory(BlockCategory category, bool enabled) async {
    await init();
    await _loadFromDisk();
    final set = _data.blockedCategories.toSet();
    if (enabled) {
      set.add(category.id);
    } else {
      set.remove(category.id);
    }
    _data = _data.copyWith(blockedCategories: set.toList()..sort());
    await _persist();
  }

  Future<void> addBlockDomain(String familyId, String domain) async {
    await init();
    final session = _session;
    if (session == null) throw Exception('Not signed in');
    final cleaned = _normalizeDomain(domain);
    if (cleaned.isEmpty) throw Exception('Invalid domain');
    final exists = _data.blockList.any(
      (e) => e.familyId == familyId && e.domain == cleaned,
    );
    if (exists) return;
    final entry = BlockListEntry(
      id: _uuid.v4(),
      familyId: familyId,
      domain: cleaned,
      createdBy: session.id,
      createdAt: DateTime.now().toUtc(),
    );
    _data = _data.copyWith(blockList: [entry, ..._data.blockList]);
    await _persist();
  }

  Future<void> removeBlockDomain(String entryId) async {
    await init();
    _data = _data.copyWith(
      blockList: _data.blockList.where((e) => e.id != entryId).toList(),
    );
    await _persist();
  }

  Future<List<BlockedAppEntry>> fetchBlockedApps(String familyId) async {
    await init();
    await _loadFromDisk();
    return _data.blockedApps.where((e) => e.familyId == familyId).toList();
  }

  Future<List<String>> fetchBlockedAppPackages(String familyId) async {
    final apps = await fetchBlockedApps(familyId);
    return apps.map((e) => e.packageName).toList();
  }

  Future<void> addBlockedApp({
    required String familyId,
    required String packageName,
    String appLabel = '',
  }) async {
    await init();
    final pkg = packageName.trim();
    if (pkg.isEmpty) throw Exception('Invalid package name');
    final exists = _data.blockedApps.any((e) => e.packageName == pkg);
    if (exists) return;
    final entry = BlockedAppEntry(
      id: _uuid.v4(),
      familyId: familyId,
      packageName: pkg,
      appLabel: appLabel.trim().isEmpty ? pkg : appLabel.trim(),
      createdAt: DateTime.now().toUtc(),
    );
    _data = _data.copyWith(blockedApps: [entry, ..._data.blockedApps]);
    await _persist();
  }

  Future<void> removeBlockedApp(String entryId) async {
    await init();
    _data = _data.copyWith(
      blockedApps: _data.blockedApps.where((e) => e.id != entryId).toList(),
    );
    await _persist();
  }

  Future<List<DomainLog>> fetchDomainLogs({
    required String familyId,
    String? childId,
    int? limit = 100,
  }) async {
    await init();
    await _loadFromDisk();
    var logs = _data.domainLogs.where((e) => e.familyId == familyId);
    if (childId != null) {
      logs = logs.where((e) => e.childId == childId);
    }
    final list = logs.toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return limit == null ? list : list.take(limit).toList();
  }

  Future<List<AppUsageLog>> fetchAppUsageLogs({
    required String familyId,
    String? childId,
    int? limit = 100,
  }) async {
    await init();
    await _loadFromDisk();
    var logs = _data.appUsageLogs.where((e) => e.familyId == familyId);
    if (childId != null) {
      logs = logs.where((e) => e.childId == childId);
    }
    final list = logs.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return limit == null ? list : list.take(limit).toList();
  }

  Future<void> insertDomainLog({
    required String familyId,
    required String domain,
    required String action,
    String? id,
    String? childId,
    DateTime? occurredAt,
  }) async {
    await init();
    final profileId = childId ?? _session?.id;
    if (profileId == null) {
      throw Exception('Sign in before recording activity.');
    }
    if (id != null && _data.domainLogs.any((log) => log.id == id)) return;
    final log = DomainLog(
      id: id ?? _uuid.v4(),
      childId: profileId,
      familyId: familyId,
      domain: domain.toLowerCase(),
      action: action,
      occurredAt: (occurredAt ?? DateTime.now()).toUtc(),
    );
    final logs = [log, ..._data.domainLogs].take(500).toList();
    _data = _data.copyWith(domainLogs: logs);
    await _persist();
  }

  Future<void> insertAppUsageLog({
    required String familyId,
    required String packageName,
    required String appLabel,
    required DateTime startedAt,
    String? id,
    String? childId,
    DateTime? endedAt,
    int? durationSeconds,
  }) async {
    await init();
    final profileId = childId ?? _session?.id;
    if (profileId == null) {
      throw Exception('Sign in before recording app usage.');
    }
    if (id != null && _data.appUsageLogs.any((log) => log.id == id)) return;
    final log = AppUsageLog(
      id: id ?? _uuid.v4(),
      childId: profileId,
      familyId: familyId,
      packageName: packageName,
      appLabel: appLabel,
      startedAt: startedAt.toUtc(),
      endedAt: endedAt?.toUtc(),
      durationSeconds: durationSeconds,
    );
    final logs = [log, ..._data.appUsageLogs].take(500).toList();
    _data = _data.copyWith(appUsageLogs: logs);
    await _persist();
  }

  String _normalizeDomain(String input) {
    var d = input.trim().toLowerCase();
    d = d.replaceFirst(RegExp(r'^https?://'), '');
    d = d.split('/').first;
    d = d.split(':').first;
    if (d.startsWith('www.')) d = d.substring(4);
    return d;
  }
}
