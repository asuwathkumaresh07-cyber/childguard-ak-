import 'categories.dart';

class Profile {
  final String id;
  final String role;
  final String displayName;
  final String email;

  const Profile({
    required this.id,
    required this.role,
    required this.displayName,
    this.email = '',
  });

  bool get isParent => role == 'parent';
  bool get isChild => role == 'child';

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'display_name': displayName,
        'email': email,
      };

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        role: json['role'] as String,
        displayName: (json['display_name'] as String?) ?? '',
        email: (json['email'] as String?) ?? '',
      );
}

/// Local-only login record for the offline demo backend.
class LocalAccount {
  final String id;
  final String role;
  final String displayName;
  final String email;
  final String passwordSalt;
  final String passwordHash;

  const LocalAccount({
    required this.id,
    required this.role,
    required this.displayName,
    required this.email,
    required this.passwordSalt,
    required this.passwordHash,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'display_name': displayName,
        'email': email,
        'password_salt': passwordSalt,
        'password_hash': passwordHash,
      };

  factory LocalAccount.fromJson(Map<String, dynamic> json) => LocalAccount(
        id: json['id'] as String,
        role: json['role'] as String,
        displayName: (json['display_name'] as String?) ?? '',
        email: json['email'] as String,
        passwordSalt: json['password_salt'] as String,
        passwordHash: json['password_hash'] as String,
      );
}

class Family {
  final String id;
  final String ownerId;
  final String name;

  const Family({
    required this.id,
    required this.ownerId,
    required this.name,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'owner_id': ownerId,
        'name': name,
      };

  factory Family.fromJson(Map<String, dynamic> json) => Family(
        id: json['id'] as String,
        ownerId: json['owner_id'] as String,
        name: (json['name'] as String?) ?? 'My Family',
      );
}

class FamilyMember {
  final String id;
  final String familyId;
  final String profileId;
  final Profile? profile;

  const FamilyMember({
    required this.id,
    required this.familyId,
    required this.profileId,
    this.profile,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'family_id': familyId,
        'profile_id': profileId,
        'profiles': profile?.toJson(),
      };

  factory FamilyMember.fromJson(Map<String, dynamic> json) => FamilyMember(
        id: json['id'] as String,
        familyId: json['family_id'] as String,
        profileId: json['profile_id'] as String,
        profile: json['profiles'] is Map<String, dynamic>
            ? Profile.fromJson(json['profiles'] as Map<String, dynamic>)
            : null,
      );
}

class PairCodeResult {
  final String code;
  final DateTime expiresAt;
  final String familyId;

  const PairCodeResult({
    required this.code,
    required this.expiresAt,
    required this.familyId,
  });

  factory PairCodeResult.fromJson(Map<String, dynamic> json) => PairCodeResult(
        code: json['code'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
        familyId: json['family_id'] as String,
      );
}

class ProtectionControlCode {
  final String code;
  final String requestedAction;
  final DateTime expiresAt;

  const ProtectionControlCode({
    required this.code,
    required this.requestedAction,
    required this.expiresAt,
  });

  factory ProtectionControlCode.fromJson(Map<String, dynamic> json) =>
      ProtectionControlCode(
        code: json['code'] as String,
        requestedAction: json['requested_action'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );
}

class ChildDeviceStatus {
  final String childId;
  final String familyId;
  final bool vpnEnabled;
  final bool usageAccessEnabled;
  final bool accessibilityEnabled;
  final bool locationSharingEnabled;
  final DateTime lastSeenAt;

  const ChildDeviceStatus({
    required this.childId,
    required this.familyId,
    required this.vpnEnabled,
    required this.usageAccessEnabled,
    required this.accessibilityEnabled,
    this.locationSharingEnabled = false,
    required this.lastSeenAt,
  });

  factory ChildDeviceStatus.fromJson(Map<String, dynamic> json) =>
      ChildDeviceStatus(
        childId: json['child_id'] as String,
        familyId: json['family_id'] as String,
        vpnEnabled: json['vpn_enabled'] as bool,
        usageAccessEnabled: json['usage_access_enabled'] as bool,
        accessibilityEnabled: json['accessibility_enabled'] as bool,
        locationSharingEnabled:
            json['location_sharing_enabled'] as bool? ?? false,
        lastSeenAt: DateTime.parse(json['last_seen_at'] as String),
      );
}

class ChildTamperEvent {
  final String id;
  final String childId;
  final String familyId;
  final String eventType;
  final DateTime occurredAt;

  const ChildTamperEvent({
    required this.id,
    required this.childId,
    required this.familyId,
    required this.eventType,
    required this.occurredAt,
  });

  factory ChildTamperEvent.fromJson(Map<String, dynamic> json) =>
      ChildTamperEvent(
        id: json['id'] as String,
        childId: json['child_id'] as String,
        familyId: json['family_id'] as String,
        eventType: json['event_type'] as String,
        occurredAt: DateTime.parse(json['occurred_at'] as String),
      );
}

class BlockListEntry {
  final String id;
  final String familyId;
  final String domain;
  final String createdBy;
  final DateTime createdAt;

  const BlockListEntry({
    required this.id,
    required this.familyId,
    required this.domain,
    required this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'family_id': familyId,
        'domain': domain,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
      };

  factory BlockListEntry.fromJson(Map<String, dynamic> json) => BlockListEntry(
        id: json['id'] as String,
        familyId: json['family_id'] as String,
        domain: json['domain'] as String,
        createdBy: json['created_by'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class BlockedAppEntry {
  final String id;
  final String familyId;
  final String packageName;
  final String appLabel;
  final DateTime createdAt;

  const BlockedAppEntry({
    required this.id,
    required this.familyId,
    required this.packageName,
    required this.appLabel,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'family_id': familyId,
        'package_name': packageName,
        'app_label': appLabel,
        'created_at': createdAt.toIso8601String(),
      };

  factory BlockedAppEntry.fromJson(Map<String, dynamic> json) =>
      BlockedAppEntry(
        id: json['id'] as String,
        familyId: json['family_id'] as String,
        packageName: json['package_name'] as String,
        appLabel: (json['app_label'] as String?) ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class BlockedCategoryEntry {
  final String id;
  final String familyId;
  final String category;
  final String createdBy;
  final DateTime createdAt;

  const BlockedCategoryEntry({
    required this.id,
    required this.familyId,
    required this.category,
    required this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'family_id': familyId,
        'category': category,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
      };

  factory BlockedCategoryEntry.fromJson(Map<String, dynamic> json) =>
      BlockedCategoryEntry(
        id: json['id'] as String,
        familyId: json['family_id'] as String,
        category: json['category'] as String,
        createdBy: (json['created_by'] as String?) ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class DomainLog {
  final String id;
  final String childId;
  final String familyId;
  final String domain;
  final String action;
  final DateTime occurredAt;

  const DomainLog({
    required this.id,
    required this.childId,
    required this.familyId,
    required this.domain,
    required this.action,
    required this.occurredAt,
  });

  bool get isBlocked => action == 'blocked';

  Map<String, dynamic> toJson() => {
        'id': id,
        'child_id': childId,
        'family_id': familyId,
        'domain': domain,
        'action': action,
        'occurred_at': occurredAt.toIso8601String(),
      };

  factory DomainLog.fromJson(Map<String, dynamic> json) => DomainLog(
        id: json['id'] as String,
        childId: json['child_id'] as String,
        familyId: json['family_id'] as String,
        domain: json['domain'] as String,
        action: json['action'] as String,
        occurredAt: DateTime.parse(json['occurred_at'] as String),
      );
}

class AppUsageLog {
  final String id;
  final String childId;
  final String familyId;
  final String packageName;
  final String appLabel;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? durationSeconds;

  const AppUsageLog({
    required this.id,
    required this.childId,
    required this.familyId,
    required this.packageName,
    required this.appLabel,
    required this.startedAt,
    this.endedAt,
    this.durationSeconds,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'child_id': childId,
        'family_id': familyId,
        'package_name': packageName,
        'app_label': appLabel,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt?.toIso8601String(),
        'duration_seconds': durationSeconds,
      };

  factory AppUsageLog.fromJson(Map<String, dynamic> json) => AppUsageLog(
        id: json['id'] as String,
        childId: json['child_id'] as String,
        familyId: json['family_id'] as String,
        packageName: json['package_name'] as String,
        appLabel: (json['app_label'] as String?) ?? '',
        startedAt: DateTime.parse(json['started_at'] as String),
        endedAt: json['ended_at'] != null
            ? DateTime.parse(json['ended_at'] as String)
            : null,
        durationSeconds: json['duration_seconds'] as int?,
      );
}

class AppTimeLimit {
  final String id;
  final String familyId;
  final String childId;
  final String packageName;
  final String appLabel;
  final int dailyLimitSeconds;
  final DateTime updatedAt;

  const AppTimeLimit({
    required this.id,
    required this.familyId,
    required this.childId,
    required this.packageName,
    required this.appLabel,
    required this.dailyLimitSeconds,
    required this.updatedAt,
  });

  factory AppTimeLimit.fromJson(Map<String, dynamic> json) => AppTimeLimit(
        id: json['id'] as String,
        familyId: json['family_id'] as String,
        childId: json['child_id'] as String,
        packageName: json['package_name'] as String,
        appLabel: (json['app_label'] as String?) ?? '',
        dailyLimitSeconds: json['daily_limit_seconds'] as int,
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}

class ExtraTimeRequest {
  final String id;
  final String familyId;
  final String childId;
  final String packageName;
  final String appLabel;
  final int requestedMinutes;
  final int? grantedMinutes;
  final String status;
  final DateTime requestedAt;
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final String? tradeSuggestion;

  const ExtraTimeRequest({
    required this.id,
    required this.familyId,
    required this.childId,
    required this.packageName,
    required this.appLabel,
    required this.requestedMinutes,
    required this.grantedMinutes,
    required this.status,
    required this.requestedAt,
    required this.resolvedAt,
    required this.resolvedBy,
    this.tradeSuggestion,
  });

  factory ExtraTimeRequest.fromJson(Map<String, dynamic> json) =>
      ExtraTimeRequest(
        id: json['id'] as String,
        familyId: json['family_id'] as String,
        childId: json['child_id'] as String,
        packageName: json['package_name'] as String,
        appLabel: (json['app_label'] as String?) ?? '',
        requestedMinutes: json['requested_minutes'] as int,
        grantedMinutes: json['granted_minutes'] as int?,
        status: json['status'] as String,
        requestedAt: DateTime.parse(json['requested_at'] as String),
        resolvedAt: json['resolved_at'] != null
            ? DateTime.parse(json['resolved_at'] as String)
            : null,
        resolvedBy: json['resolved_by'] as String?,
        tradeSuggestion: json['trade_suggestion'] as String?,
      );
}

class VpnControlRequest {
  final String id;
  final String familyId;
  final String childId;
  final String requestedAction;
  final String status;
  final DateTime requestedAt;
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final DateTime? appliedAt;

  const VpnControlRequest({
    required this.id,
    required this.familyId,
    required this.childId,
    required this.requestedAction,
    required this.status,
    required this.requestedAt,
    required this.resolvedAt,
    required this.resolvedBy,
    required this.appliedAt,
  });

  factory VpnControlRequest.fromJson(Map<String, dynamic> json) =>
      VpnControlRequest(
        id: json['id'] as String,
        familyId: json['family_id'] as String,
        childId: json['child_id'] as String,
        requestedAction: json['requested_action'] as String,
        status: json['status'] as String,
        requestedAt: DateTime.parse(json['requested_at'] as String),
        resolvedAt: json['resolved_at'] != null
            ? DateTime.parse(json['resolved_at'] as String)
            : null,
        resolvedBy: json['resolved_by'] as String?,
        appliedAt: json['applied_at'] != null
            ? DateTime.parse(json['applied_at'] as String)
            : null,
      );
}

class ChildLocation {
  final String id;
  final String familyId;
  final String childId;
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final DateTime recordedAt;

  const ChildLocation({
    required this.id,
    required this.familyId,
    required this.childId,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.recordedAt,
  });

  factory ChildLocation.fromJson(Map<String, dynamic> json) => ChildLocation(
        id: json['id'] as String,
        familyId: json['family_id'] as String,
        childId: json['child_id'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracyMeters: (json['accuracy_meters'] as num?)?.toDouble(),
        recordedAt: DateTime.parse(json['recorded_at'] as String),
      );
}

class FamilyZone {
  final String id;
  final String familyId;
  final String name;
  final String zoneType;
  final double latitude;
  final double longitude;
  final int radiusMeters;

  const FamilyZone({
    required this.id,
    required this.familyId,
    required this.name,
    required this.zoneType,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  factory FamilyZone.fromJson(Map<String, dynamic> json) => FamilyZone(
        id: json['id'] as String,
        familyId: json['family_id'] as String,
        name: json['name'] as String,
        zoneType: json['zone_type'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        radiusMeters: json['radius_meters'] as int,
      );
}

class ZoneAppRule {
  final String id;
  final String familyId;
  final String zoneId;
  final String packageName;
  final String appLabel;

  const ZoneAppRule({
    required this.id,
    required this.familyId,
    required this.zoneId,
    required this.packageName,
    required this.appLabel,
  });

  factory ZoneAppRule.fromJson(Map<String, dynamic> json) => ZoneAppRule(
        id: json['id'] as String,
        familyId: json['family_id'] as String,
        zoneId: json['zone_id'] as String,
        packageName: json['package_name'] as String,
        appLabel: (json['app_label'] as String?) ?? '',
      );
}

class ZoneEvent {
  final String id;
  final String familyId;
  final String childId;
  final String zoneId;
  final String eventType;
  final String? packageName;
  final DateTime occurredAt;

  const ZoneEvent({
    required this.id,
    required this.familyId,
    required this.childId,
    required this.zoneId,
    required this.eventType,
    required this.packageName,
    required this.occurredAt,
  });

  factory ZoneEvent.fromJson(Map<String, dynamic> json) => ZoneEvent(
        id: json['id'] as String,
        familyId: json['family_id'] as String,
        childId: json['child_id'] as String,
        zoneId: json['zone_id'] as String,
        eventType: json['event_type'] as String,
        packageName: json['package_name'] as String?,
        occurredAt: DateTime.parse(json['occurred_at'] as String),
      );
}

class ChildTask {
  final String id;
  final String familyId;
  final String childId;
  final String title;
  final String description;
  final String taskType;
  final DateTime? dueAt;
  final int points;
  final String status;
  final DateTime createdAt;
  final String? submissionPhotoPath;
  final String? submissionNote;

  const ChildTask({
    required this.id,
    required this.familyId,
    required this.childId,
    required this.title,
    required this.description,
    required this.taskType,
    required this.dueAt,
    required this.points,
    required this.status,
    required this.createdAt,
    required this.submissionPhotoPath,
    required this.submissionNote,
  });

  factory ChildTask.fromJson(Map<String, dynamic> json) {
    final submission = json['task_submissions'];
    final submissionRow = submission is List && submission.isNotEmpty
        ? submission.first as Map<String, dynamic>
        : submission is Map<String, dynamic>
            ? submission
            : null;
    return ChildTask(
      id: json['id'] as String,
      familyId: json['family_id'] as String,
      childId: json['child_id'] as String,
      title: json['title'] as String,
      description: (json['description'] as String?) ?? '',
      taskType: (json['task_type'] as String?) ?? 'task',
      dueAt: json['due_at'] != null
          ? DateTime.parse(json['due_at'] as String)
          : null,
      points: json['points'] as int,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      submissionPhotoPath: submissionRow?['photo_path'] as String?,
      submissionNote: submissionRow?['note'] as String?,
    );
  }
}

class ChildMoodCheckin {
  final String id;
  final String familyId;
  final String childId;
  final String mood;
  final String note;
  final DateTime createdAt;

  const ChildMoodCheckin({
    required this.id,
    required this.familyId,
    required this.childId,
    required this.mood,
    required this.note,
    required this.createdAt,
  });

  factory ChildMoodCheckin.fromJson(Map<String, dynamic> json) =>
      ChildMoodCheckin(
        id: json['id'] as String,
        familyId: json['family_id'] as String,
        childId: json['child_id'] as String,
        mood: json['mood'] as String,
        note: (json['note'] as String?) ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class ChildWeeklyInsight {
  final String id;
  final String familyId;
  final String childId;
  final DateTime weekStart;
  final String summary;
  final int trustScore;
  final bool moodAlert;
  final String? moodAlertReason;

  const ChildWeeklyInsight({
    required this.id,
    required this.familyId,
    required this.childId,
    required this.weekStart,
    required this.summary,
    required this.trustScore,
    this.moodAlert = false,
    this.moodAlertReason,
  });

  factory ChildWeeklyInsight.fromJson(Map<String, dynamic> json) =>
      ChildWeeklyInsight(
        id: json['id'] as String,
        familyId: json['family_id'] as String,
        childId: json['child_id'] as String,
        weekStart: DateTime.parse(json['week_start'] as String),
        summary: json['summary'] as String,
        trustScore: json['trust_score'] as int,
        moodAlert: json['mood_alert'] as bool? ?? false,
        moodAlertReason: json['mood_alert_reason'] as String?,
      );
}

class ChildStreak {
  final String childId;
  final String familyId;
  final int currentStreak;
  final int bestStreak;
  final int totalPoints;
  final int bonusTimeMinutes;
  final int appUnlockCredits;

  const ChildStreak({
    required this.childId,
    required this.familyId,
    required this.currentStreak,
    required this.bestStreak,
    required this.totalPoints,
    this.bonusTimeMinutes = 0,
    this.appUnlockCredits = 0,
  });

  factory ChildStreak.fromJson(Map<String, dynamic> json) => ChildStreak(
        childId: json['child_id'] as String,
        familyId: json['family_id'] as String,
        currentStreak: json['current_streak'] as int,
        bestStreak: json['best_streak'] as int,
        totalPoints: json['total_points'] as int,
        bonusTimeMinutes: json['bonus_time_minutes'] as int? ?? 0,
        appUnlockCredits: json['app_unlock_credits'] as int? ?? 0,
      );
}

class ChildTemporaryAppUnlock {
  final String id;
  final String familyId;
  final String childId;
  final String packageName;
  final DateTime expiresAt;

  const ChildTemporaryAppUnlock({
    required this.id,
    required this.familyId,
    required this.childId,
    required this.packageName,
    required this.expiresAt,
  });

  factory ChildTemporaryAppUnlock.fromJson(Map<String, dynamic> json) =>
      ChildTemporaryAppUnlock(
        id: json['id'] as String,
        familyId: json['family_id'] as String,
        childId: json['child_id'] as String,
        packageName: json['package_name'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );
}

class ChildAutonomySettings {
  final String childId;
  final String familyId;
  final bool enabled;
  final int minTrustScore;
  final int dailyExtraMinutesCap;

  const ChildAutonomySettings({
    required this.childId,
    required this.familyId,
    required this.enabled,
    required this.minTrustScore,
    required this.dailyExtraMinutesCap,
  });

  factory ChildAutonomySettings.fromJson(Map<String, dynamic> json) =>
      ChildAutonomySettings(
        childId: json['child_id'] as String,
        familyId: json['family_id'] as String,
        enabled: json['enabled'] as bool,
        minTrustScore: json['min_trust_score'] as int,
        dailyExtraMinutesCap: json['daily_extra_minutes_cap'] as int,
      );
}

class FamilyStoreSnapshot {
  final Family? family;
  final List<LocalAccount> accounts;
  final List<Profile> profiles;
  final List<FamilyMember> members;
  final List<BlockListEntry> blockList;
  final List<String> blockedCategories;
  final List<BlockedAppEntry> blockedApps;
  final List<DomainLog> domainLogs;
  final List<AppUsageLog> appUsageLogs;
  final String pairCode;

  const FamilyStoreSnapshot({
    this.family,
    this.accounts = const [],
    this.profiles = const [],
    this.members = const [],
    this.blockList = const [],
    this.blockedCategories = const [],
    this.blockedApps = const [],
    this.domainLogs = const [],
    this.appUsageLogs = const [],
    this.pairCode = '1234',
  });

  List<BlockCategory> get categories => blockedCategories
      .map(BlockCategoryX.fromId)
      .whereType<BlockCategory>()
      .toList();

  Map<String, dynamic> toJson() => {
        'family': family?.toJson(),
        'accounts': accounts.map((e) => e.toJson()).toList(),
        'profiles': profiles.map((e) => e.toJson()).toList(),
        'members': members.map((e) => e.toJson()).toList(),
        'block_list': blockList.map((e) => e.toJson()).toList(),
        'blocked_categories': blockedCategories,
        'blocked_apps': blockedApps.map((e) => e.toJson()).toList(),
        'domain_logs': domainLogs.map((e) => e.toJson()).toList(),
        'app_usage_logs': appUsageLogs.map((e) => e.toJson()).toList(),
        'pair_code': pairCode,
      };

  factory FamilyStoreSnapshot.fromJson(Map<String, dynamic> json) {
    return FamilyStoreSnapshot(
      family: json['family'] is Map<String, dynamic>
          ? Family.fromJson(json['family'] as Map<String, dynamic>)
          : null,
      accounts: (json['accounts'] as List? ?? [])
          .map((e) => LocalAccount.fromJson(e as Map<String, dynamic>))
          .toList(),
      profiles: (json['profiles'] as List? ?? [])
          .map((e) => Profile.fromJson(e as Map<String, dynamic>))
          .toList(),
      members: (json['members'] as List? ?? [])
          .map((e) => FamilyMember.fromJson(e as Map<String, dynamic>))
          .toList(),
      blockList: (json['block_list'] as List? ?? [])
          .map((e) => BlockListEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      blockedCategories: (json['blocked_categories'] as List? ?? [])
          .map((e) => e.toString())
          .toList(),
      blockedApps: (json['blocked_apps'] as List? ?? [])
          .map((e) => BlockedAppEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      domainLogs: (json['domain_logs'] as List? ?? [])
          .map((e) => DomainLog.fromJson(e as Map<String, dynamic>))
          .toList(),
      appUsageLogs: (json['app_usage_logs'] as List? ?? [])
          .map((e) => AppUsageLog.fromJson(e as Map<String, dynamic>))
          .toList(),
      pairCode: (json['pair_code'] as String?) ?? '1234',
    );
  }

  FamilyStoreSnapshot copyWith({
    Family? family,
    List<LocalAccount>? accounts,
    List<Profile>? profiles,
    List<FamilyMember>? members,
    List<BlockListEntry>? blockList,
    List<String>? blockedCategories,
    List<BlockedAppEntry>? blockedApps,
    List<DomainLog>? domainLogs,
    List<AppUsageLog>? appUsageLogs,
    String? pairCode,
  }) {
    return FamilyStoreSnapshot(
      family: family ?? this.family,
      accounts: accounts ?? this.accounts,
      profiles: profiles ?? this.profiles,
      members: members ?? this.members,
      blockList: blockList ?? this.blockList,
      blockedCategories: blockedCategories ?? this.blockedCategories,
      blockedApps: blockedApps ?? this.blockedApps,
      domainLogs: domainLogs ?? this.domainLogs,
      appUsageLogs: appUsageLogs ?? this.appUsageLogs,
      pairCode: pairCode ?? this.pairCode,
    );
  }
}
