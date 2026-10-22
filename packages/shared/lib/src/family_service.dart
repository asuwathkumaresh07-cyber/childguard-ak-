import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'categories.dart';
import 'config.dart';
import 'local_store.dart';
import 'models.dart';
import 'supabase_service.dart';

/// Unified FamilyService supporting Supabase Cloud database with graceful
/// fallback to LocalFamilyStore when running in demo/offline mode.
class FamilyService {
  FamilyService([LocalFamilyStore? store, SupabaseService? supabase])
      : _store = store ?? LocalFamilyStore.instance,
        _supabase = supabase ?? SupabaseService.instance;

  final LocalFamilyStore _store;
  final SupabaseService _supabase;

  bool get isUsingSupabase =>
      SupabaseConfig.isRealSupabaseConfigured && _supabase.isInitialized;

  String? get userId =>
      isUsingSupabase ? _supabase.currentAuthUser?.id : _store.session?.id;

  Future<void> reload() async {
    if (isUsingSupabase) {
      // Supabase is stateless/reactive, no local disk reload needed
      return;
    }
    await _store.reload();
  }

  Future<Profile?> fetchMyProfile() async {
    if (isUsingSupabase) {
      return _supabase.fetchMyProfile();
    }
    return _store.fetchMyProfile();
  }

  Future<Family?> fetchMyFamily() async {
    if (isUsingSupabase) {
      return _supabase.fetchMyFamily();
    }
    return _store.fetchMyFamily();
  }

  Future<List<FamilyMember>> fetchChildren(String familyId) async {
    if (isUsingSupabase) {
      return _supabase.fetchChildren(familyId);
    }
    return _store.fetchChildren(familyId);
  }

  Future<PairCodeResult> createPairCode({int minutes = 30}) async {
    if (isUsingSupabase) {
      return _supabase.createPairCode(minutes: minutes);
    }
    return _store.createPairCode(minutes: minutes);
  }

  Future<String> redeemPairCode(String code) async {
    if (isUsingSupabase) {
      return _supabase.redeemPairCode(code);
    }
    return _store.redeemPairCode(code);
  }

  Future<ProtectionControlCode> createProtectionControlCode({
    required String familyId,
    required String childId,
    required String requestedAction,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.createProtectionControlCode(
      familyId: familyId,
      childId: childId,
      requestedAction: requestedAction,
    );
  }

  Future<String> redeemProtectionControlCode({
    required String code,
    required String requestedAction,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.redeemProtectionControlCode(
      code: code,
      requestedAction: requestedAction,
    );
  }

  Future<ChildDeviceStatus?> fetchChildDeviceStatus(String childId) {
    _requireSupabaseForUsageControls();
    return _supabase.fetchChildDeviceStatus(childId);
  }

  Future<String> fetchChildProtectionMode({
    required String familyId,
    required String childId,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.fetchChildProtectionMode(
      familyId: familyId,
      childId: childId,
    );
  }

  Future<void> setChildProtectionMode({
    required String familyId,
    required String childId,
    required String mode,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.setChildProtectionMode(
      familyId: familyId,
      childId: childId,
      mode: mode,
    );
  }

  Future<List<ChildTamperEvent>> fetchChildTamperEvents({
    required String familyId,
    required String childId,
    int limit = 20,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.fetchChildTamperEvents(
      familyId: familyId,
      childId: childId,
      limit: limit,
    );
  }

  Future<void> reportChildDeviceStatus({
    required bool vpnEnabled,
    required bool usageAccessEnabled,
    required bool accessibilityEnabled,
    required bool locationSharingEnabled,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.reportChildDeviceStatus(
      vpnEnabled: vpnEnabled,
      usageAccessEnabled: usageAccessEnabled,
      accessibilityEnabled: accessibilityEnabled,
      locationSharingEnabled: locationSharingEnabled,
    );
  }

  // ---------------------------------------------------------------------------
  // Specific Domain Filtering
  // ---------------------------------------------------------------------------

  Future<List<BlockListEntry>> fetchBlockList(String familyId) async {
    if (isUsingSupabase) {
      return _supabase.fetchBlockList(familyId);
    }
    return _store.fetchBlockList(familyId);
  }

  /// Returns effective blocked domains (custom domains + active category domains)
  Future<List<String>> fetchBlockDomains(String familyId) async {
    if (isUsingSupabase) {
      return _supabase.fetchEffectiveBlockedDomains(familyId);
    }
    return _store.fetchBlockDomains(familyId);
  }

  Future<List<String>> fetchChildBlockDomains({
    required String familyId,
    required String childId,
  }) async {
    final domains = await fetchBlockDomains(familyId);
    if (!isUsingSupabase) return domains;
    return {
      ...domains,
      ...await _supabase.fetchChildBlockedDomainOverrides(
        familyId: familyId,
        childId: childId,
      ),
    }.toList()
      ..sort();
  }

  Future<void> addBlockDomain(String familyId, String domain) async {
    if (isUsingSupabase) {
      return _supabase.addBlockDomain(familyId, domain);
    }
    return _store.addBlockDomain(familyId, domain);
  }

  Future<void> addChildBlockedDomain({
    required String familyId,
    required String childId,
    required String domain,
  }) async {
    if (isUsingSupabase) {
      return _supabase.addChildBlockedDomain(
        familyId: familyId,
        childId: childId,
        domain: domain,
      );
    }
    return _store.addBlockDomain(familyId, domain);
  }

  Future<void> removeChildBlockedDomain({
    required String familyId,
    required String childId,
    required String domain,
  }) async {
    if (isUsingSupabase) {
      return _supabase.removeChildBlockedDomain(
        familyId: familyId,
        childId: childId,
        domain: domain,
      );
    }
    final entries = await _store.fetchBlockList(familyId);
    final entry = entries
        .where((item) => item.domain.toLowerCase() == domain.toLowerCase())
        .firstOrNull;
    if (entry != null) await _store.removeBlockDomain(entry.id);
  }

  Future<void> removeBlockDomain(String entryId) async {
    if (isUsingSupabase) {
      return _supabase.removeBlockDomain(entryId);
    }
    return _store.removeBlockDomain(entryId);
  }

  // ---------------------------------------------------------------------------
  // Category-Based Filtering
  // ---------------------------------------------------------------------------

  Future<List<String>> fetchBlockedCategories([String? familyId]) async {
    if (isUsingSupabase && familyId != null) {
      return _supabase.fetchBlockedCategories(familyId);
    }
    return _store.fetchBlockedCategories();
  }

  Future<void> setBlockedCategories(
    List<String> categoryIds, {
    String? familyId,
  }) async {
    if (isUsingSupabase && familyId != null) {
      return _supabase.setBlockedCategories(
        familyId: familyId,
        categoryIds: categoryIds,
      );
    }
    return _store.setBlockedCategories(categoryIds);
  }

  Future<void> toggleCategory(
    BlockCategory category,
    bool enabled, {
    String? familyId,
  }) async {
    if (isUsingSupabase && familyId != null) {
      return _supabase.toggleCategory(
        familyId: familyId,
        category: category,
        enabled: enabled,
      );
    }
    return _store.toggleCategory(category, enabled);
  }

  Future<List<String>> fetchChildBlockedCategories({
    required String familyId,
    required String childId,
  }) async {
    final categories = await fetchBlockedCategories(familyId);
    if (!isUsingSupabase) return categories;
    return {
      ...categories,
      ...await _supabase.fetchChildBlockedCategories(
        familyId: familyId,
        childId: childId,
      ),
    }.toList()
      ..sort();
  }

  Future<void> setChildBlockedCategories({
    required String familyId,
    required String childId,
    required List<String> categoryIds,
  }) async {
    if (isUsingSupabase) {
      return _supabase.setChildBlockedCategories(
        familyId: familyId,
        childId: childId,
        categoryIds: categoryIds,
      );
    }
    return _store.setBlockedCategories(categoryIds);
  }

  // ---------------------------------------------------------------------------
  // App Blocking
  // ---------------------------------------------------------------------------

  Future<List<BlockedAppEntry>> fetchBlockedApps(String familyId) async {
    if (isUsingSupabase) {
      return _supabase.fetchBlockedApps(familyId);
    }
    return _store.fetchBlockedApps(familyId);
  }

  Future<List<String>> fetchBlockedAppPackages(String familyId) async {
    if (isUsingSupabase) {
      return _supabase.fetchBlockedAppPackages(familyId);
    }
    return _store.fetchBlockedAppPackages(familyId);
  }

  Future<List<String>> fetchChildBlockedAppPackages({
    required String familyId,
    required String childId,
  }) async {
    final packages = await fetchBlockedAppPackages(familyId);
    if (!isUsingSupabase) return packages;
    return {
      ...packages,
      ...await _supabase.fetchChildBlockedAppPackages(
        familyId: familyId,
        childId: childId,
      ),
    }.toList();
  }

  Future<void> addBlockedApp({
    required String familyId,
    required String packageName,
    String appLabel = '',
  }) async {
    if (isUsingSupabase) {
      return _supabase.addBlockedApp(
        familyId: familyId,
        packageName: packageName,
        appLabel: appLabel,
      );
    }
    return _store.addBlockedApp(
      familyId: familyId,
      packageName: packageName,
      appLabel: appLabel,
    );
  }

  Future<void> addChildBlockedApp({
    required String familyId,
    required String childId,
    required String packageName,
    required String appLabel,
  }) async {
    if (isUsingSupabase) {
      return _supabase.addChildBlockedApp(
        familyId: familyId,
        childId: childId,
        packageName: packageName,
        appLabel: appLabel,
      );
    }
    return _store.addBlockedApp(
      familyId: familyId,
      packageName: packageName,
      appLabel: appLabel,
    );
  }

  Future<void> removeChildBlockedApp({
    required String familyId,
    required String childId,
    required String packageName,
  }) async {
    if (isUsingSupabase) {
      return _supabase.removeChildBlockedApp(
        familyId: familyId,
        childId: childId,
        packageName: packageName,
      );
    }
    final entries = await _store.fetchBlockedApps(familyId);
    final entry =
        entries.where((item) => item.packageName == packageName).firstOrNull;
    if (entry != null) await _store.removeBlockedApp(entry.id);
  }

  Future<void> removeBlockedApp(String entryId) async {
    if (isUsingSupabase) {
      return _supabase.removeBlockedApp(entryId);
    }
    return _store.removeBlockedApp(entryId);
  }

  // ---------------------------------------------------------------------------
  // Child Network Activities Monitoring (Domain Logs)
  // ---------------------------------------------------------------------------

  Future<List<DomainLog>> fetchDomainLogs({
    required String familyId,
    String? childId,
    int? limit = 100,
  }) async {
    if (isUsingSupabase) {
      return _supabase.fetchDomainLogs(
        familyId: familyId,
        childId: childId,
        limit: limit,
      );
    }
    return _store.fetchDomainLogs(
      familyId: familyId,
      childId: childId,
      limit: limit,
    );
  }

  Future<void> insertDomainLog({
    required String familyId,
    required String domain,
    required String action,
    String? id,
    String? childId,
    DateTime? occurredAt,
  }) async {
    if (isUsingSupabase) {
      return _supabase.insertDomainLog(
        familyId: familyId,
        domain: domain,
        action: action,
        id: id,
        childId: childId,
        occurredAt: occurredAt,
      );
    }
    return _store.insertDomainLog(
      familyId: familyId,
      domain: domain,
      action: action,
      id: id,
      childId: childId,
      occurredAt: occurredAt,
    );
  }

  // ---------------------------------------------------------------------------
  // App Usage Logs
  // ---------------------------------------------------------------------------

  Future<List<AppUsageLog>> fetchAppUsageLogs({
    required String familyId,
    String? childId,
    int? limit = 100,
  }) async {
    if (isUsingSupabase) {
      return _supabase.fetchAppUsageLogs(
        familyId: familyId,
        childId: childId,
        limit: limit,
      );
    }
    return _store.fetchAppUsageLogs(
      familyId: familyId,
      childId: childId,
      limit: limit,
    );
  }

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
    if (isUsingSupabase) {
      return _supabase.insertAppUsageLog(
        familyId: familyId,
        packageName: packageName,
        appLabel: appLabel,
        startedAt: startedAt,
        id: id,
        endedAt: endedAt,
        durationSeconds: durationSeconds,
        childId: childId,
      );
    }
    return _store.insertAppUsageLog(
      familyId: familyId,
      packageName: packageName,
      appLabel: appLabel,
      startedAt: startedAt,
      id: id,
      endedAt: endedAt,
      durationSeconds: durationSeconds,
    );
  }

  Future<List<AppTimeLimit>> fetchAppTimeLimits({
    required String familyId,
    required String childId,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.fetchAppTimeLimits(
      familyId: familyId,
      childId: childId,
    );
  }

  Future<void> saveAppTimeLimit({
    required String familyId,
    required String childId,
    required String packageName,
    required String appLabel,
    required int dailyLimitSeconds,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.saveAppTimeLimit(
      familyId: familyId,
      childId: childId,
      packageName: packageName,
      appLabel: appLabel,
      dailyLimitSeconds: dailyLimitSeconds,
    );
  }

  Future<void> removeAppTimeLimit({
    required String familyId,
    required String id,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.removeAppTimeLimit(familyId: familyId, id: id);
  }

  Future<List<ExtraTimeRequest>> fetchExtraTimeRequests({
    required String familyId,
    String? childId,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.fetchExtraTimeRequests(
      familyId: familyId,
      childId: childId,
    );
  }

  Future<String> createExtraTimeRequest({
    required String familyId,
    required String childId,
    required String packageName,
    required String appLabel,
    required int requestedMinutes,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.createExtraTimeRequest(
      familyId: familyId,
      childId: childId,
      packageName: packageName,
      appLabel: appLabel,
      requestedMinutes: requestedMinutes,
    );
  }

  Future<void> resolveExtraTimeRequest({
    required String familyId,
    required String id,
    required bool approve,
    int? grantedMinutes,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.resolveExtraTimeRequest(
      familyId: familyId,
      id: id,
      approve: approve,
      grantedMinutes: grantedMinutes,
    );
  }

  Future<List<VpnControlRequest>> fetchVpnControlRequests({
    required String familyId,
    String? childId,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.fetchVpnControlRequests(
      familyId: familyId,
      childId: childId,
    );
  }

  Future<void> createVpnControlRequest({
    required String familyId,
    required String childId,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.createVpnControlRequest(
      familyId: familyId,
      childId: childId,
    );
  }

  Future<void> resolveVpnControlRequest({
    required String familyId,
    required String id,
    required bool approve,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.resolveVpnControlRequest(
      familyId: familyId,
      id: id,
      approve: approve,
    );
  }

  Future<void> markVpnControlRequestApplied({
    required String id,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.markVpnControlRequestApplied(
      id: id,
    );
  }

  Future<ChildLocation?> fetchLatestChildLocation(String childId) {
    _requireSupabaseForUsageControls();
    return _supabase.fetchLatestChildLocation(childId);
  }

  Future<List<ChildLocation>> fetchChildLocationHistory(
    String childId, {
    int limit = 48,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.fetchChildLocationHistory(childId, limit: limit);
  }

  RealtimeChannel? subscribeToChildLocations(
    String childId,
    void Function(ChildLocation location) onLocation,
  ) {
    if (isUsingSupabase) {
      return _supabase.subscribeToChildLocations(childId, onLocation);
    }
    return null;
  }

  Future<void> recordChildLocation({
    required String familyId,
    required String childId,
    required double latitude,
    required double longitude,
    double? accuracyMeters,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.recordChildLocation(
      familyId: familyId,
      childId: childId,
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
    );
  }

  Future<List<FamilyZone>> fetchFamilyZones(String familyId) {
    _requireSupabaseForUsageControls();
    return _supabase.fetchFamilyZones(familyId);
  }

  Future<FamilyZone> saveFamilyZone({
    required String familyId,
    String? id,
    required String name,
    required String zoneType,
    required double latitude,
    required double longitude,
    required int radiusMeters,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.saveFamilyZone(
      familyId: familyId,
      id: id,
      name: name,
      zoneType: zoneType,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
    );
  }

  Future<void> removeFamilyZone(String familyId, String zoneId) {
    _requireSupabaseForUsageControls();
    return _supabase.removeFamilyZone(familyId, zoneId);
  }

  Future<List<ZoneAppRule>> fetchZoneAppRules(String familyId) {
    _requireSupabaseForUsageControls();
    return _supabase.fetchZoneAppRules(familyId);
  }

  Future<void> saveZoneAppRule({
    required String familyId,
    required String zoneId,
    required String packageName,
    required String appLabel,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.saveZoneAppRule(
      familyId: familyId,
      zoneId: zoneId,
      packageName: packageName,
      appLabel: appLabel,
    );
  }

  Future<void> removeZoneAppRule(String ruleId) {
    _requireSupabaseForUsageControls();
    return _supabase.removeZoneAppRule(ruleId);
  }

  Future<String> recordZoneEvent({
    required String familyId,
    required String childId,
    required String zoneId,
    required String eventType,
    String? packageName,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.recordZoneEvent(
      familyId: familyId,
      childId: childId,
      zoneId: zoneId,
      eventType: eventType,
      packageName: packageName,
    );
  }

  Future<void> sendParentZoneAlert(String eventId) {
    _requireSupabaseForUsageControls();
    return _supabase.sendParentZoneAlert(eventId);
  }

  Future<List<ZoneEvent>> fetchZoneEvents({
    required String familyId,
    String? childId,
    int limit = 30,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.fetchZoneEvents(
      familyId: familyId,
      childId: childId,
      limit: limit,
    );
  }

  Future<List<ChildTask>> fetchChildTasks({
    required String familyId,
    String? childId,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.fetchChildTasks(familyId: familyId, childId: childId);
  }

  Future<void> createChildTask({
    required String familyId,
    required String childId,
    required String title,
    required String description,
    String taskType = 'task',
    DateTime? dueAt,
    int points = 10,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.createChildTask(
      familyId: familyId,
      childId: childId,
      title: title,
      description: description,
      taskType: taskType,
      dueAt: dueAt,
      points: points,
    );
  }

  Future<void> submitChildTask({
    required String taskId,
    required Uint8List photoBytes,
    required String note,
    String contentType = 'image/jpeg',
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.submitChildTask(
      taskId: taskId,
      photoBytes: photoBytes,
      note: note,
      contentType: contentType,
    );
  }

  Future<String> createTaskPhotoUrl(String path) {
    _requireSupabaseForUsageControls();
    return _supabase.createTaskPhotoUrl(path);
  }

  Future<void> reviewChildTask({
    required String familyId,
    required String taskId,
    required bool approve,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.reviewChildTask(
      familyId: familyId,
      taskId: taskId,
      approve: approve,
    );
  }

  Future<List<ChildMoodCheckin>> fetchChildMoodCheckins({
    required String familyId,
    String? childId,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.fetchChildMoodCheckins(
      familyId: familyId,
      childId: childId,
    );
  }

  Future<void> createChildMoodCheckin({
    required String familyId,
    required String childId,
    required String mood,
    String note = '',
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.createChildMoodCheckin(
      familyId: familyId,
      childId: childId,
      mood: mood,
      note: note,
    );
  }

  Future<ChildWeeklyInsight?> fetchLatestChildWeeklyInsight(String childId) {
    _requireSupabaseForUsageControls();
    return _supabase.fetchLatestChildWeeklyInsight(childId);
  }

  Future<ChildWeeklyInsight> generateChildWeeklyInsight({
    required String familyId,
    required String childId,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.generateChildWeeklyInsight(
      familyId: familyId,
      childId: childId,
    );
  }

  RealtimeChannel? subscribeToChildWeeklyInsights(
    String childId,
    void Function(ChildWeeklyInsight insight) onInsight,
  ) {
    if (isUsingSupabase) {
      return _supabase.subscribeToChildWeeklyInsights(childId, onInsight);
    }
    return null;
  }

  Future<ChildStreak?> fetchChildStreak(String childId) {
    _requireSupabaseForUsageControls();
    return _supabase.fetchChildStreak(childId);
  }

  Future<List<ChildTemporaryAppUnlock>> fetchActiveChildAppUnlocks(
    String childId,
  ) {
    _requireSupabaseForUsageControls();
    return _supabase.fetchActiveChildAppUnlocks(childId);
  }

  Future<ChildTemporaryAppUnlock> redeemChildTemporaryAppUnlock({
    required String familyId,
    required String packageName,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.redeemChildTemporaryAppUnlock(
      familyId: familyId,
      packageName: packageName,
    );
  }

  Future<ChildAutonomySettings> fetchChildAutonomySettings({
    required String familyId,
    required String childId,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.fetchChildAutonomySettings(
      familyId: familyId,
      childId: childId,
    );
  }

  Future<void> saveChildAutonomySettings({
    required String familyId,
    required String childId,
    required bool enabled,
    required int minTrustScore,
    required int dailyExtraMinutesCap,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.saveChildAutonomySettings(
      familyId: familyId,
      childId: childId,
      enabled: enabled,
      minTrustScore: minTrustScore,
      dailyExtraMinutesCap: dailyExtraMinutesCap,
    );
  }

  Future<void> saveChildAppCategory({
    required String familyId,
    required String packageName,
    required String category,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.saveChildAppCategory(
      familyId: familyId,
      packageName: packageName,
      category: category,
    );
  }

  Future<Map<String, String>> fetchChildAppCategories(String familyId) {
    _requireSupabaseForUsageControls();
    return _supabase.fetchChildAppCategories(familyId);
  }

  Future<Map<String, String>> fetchAppCategoriesForChild({
    required String familyId,
    required String childId,
  }) async {
    if (!isUsingSupabase) return {};
    final categories = await fetchChildAppCategories(familyId);
    categories.addAll(await _supabase.fetchChildAppCategoryOverrides(
      familyId: familyId,
      childId: childId,
    ));
    return categories;
  }

  Future<void> saveChildAppCategoryOverride({
    required String familyId,
    required String childId,
    required String packageName,
    required String category,
  }) {
    _requireSupabaseForUsageControls();
    return _supabase.saveChildAppCategoryOverride(
      familyId: familyId,
      childId: childId,
      packageName: packageName,
      category: category,
    );
  }

  void _requireSupabaseForUsageControls() {
    if (!isUsingSupabase) {
      throw UnsupportedError(
        'App time limits and approval requests require a connected Supabase project.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Realtime Subscriptions
  // ---------------------------------------------------------------------------

  RealtimeChannel? subscribeToRules(
    String familyId,
    void Function() onRulesChanged,
  ) {
    if (isUsingSupabase) {
      return _supabase.subscribeToBlockChanges(familyId, onRulesChanged);
    }
    return null;
  }

  RealtimeChannel? subscribeToDomainLogs(
    String familyId,
    void Function(DomainLog log) onNewLog,
  ) {
    if (isUsingSupabase) {
      return _supabase.subscribeToDomainLogs(familyId, onNewLog);
    }
    return null;
  }

  RealtimeChannel? subscribeToChildTamperEvents(
    String familyId,
    void Function(ChildTamperEvent event) onEvent,
  ) {
    if (isUsingSupabase) {
      return _supabase.subscribeToChildTamperEvents(familyId, onEvent);
    }
    return null;
  }

  RealtimeChannel? subscribeToZoneEvents(
    String familyId,
    void Function(ZoneEvent event) onEvent,
  ) {
    if (isUsingSupabase) {
      return _supabase.subscribeToZoneEvents(familyId, onEvent);
    }
    return null;
  }
}
