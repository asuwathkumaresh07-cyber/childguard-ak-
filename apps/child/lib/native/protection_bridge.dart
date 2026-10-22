import 'dart:async';

import 'package:flutter/services.dart';

class DomainEvent {
  final String domain;
  final String action;

  const DomainEvent({required this.domain, required this.action});
}

class AppUsageEvent {
  final String packageName;
  final String appLabel;
  final DateTime startedAt;
  final DateTime endedAt;
  final int durationSeconds;

  const AppUsageEvent({
    required this.packageName,
    required this.appLabel,
    required this.startedAt,
    required this.endedAt,
    required this.durationSeconds,
  });
}

class PendingDomainEvent {
  final int rowId;
  final String eventId;
  final String domain;
  final String action;
  final DateTime occurredAt;

  const PendingDomainEvent({
    required this.rowId,
    required this.eventId,
    required this.domain,
    required this.action,
    required this.occurredAt,
  });
}

class PendingUsageEvent {
  final int rowId;
  final String eventId;
  final String packageName;
  final String appLabel;
  final DateTime startedAt;
  final DateTime endedAt;
  final int durationSeconds;

  const PendingUsageEvent({
    required this.rowId,
    required this.eventId,
    required this.packageName,
    required this.appLabel,
    required this.startedAt,
    required this.endedAt,
    required this.durationSeconds,
  });
}

class ProtectionBridge {
  static const _methods = MethodChannel('com.familyguard.child/protection');
  static const _domainEvents =
      EventChannel('com.familyguard.child/domain_events');
  static const _usageEvents =
      EventChannel('com.familyguard.child/usage_events');

  Stream<DomainEvent> domainEvents() {
    return _domainEvents.receiveBroadcastStream().map((event) {
      final map = Map<String, dynamic>.from(event as Map);
      return DomainEvent(
        domain: map['domain'] as String,
        action: map['action'] as String,
      );
    });
  }

  Stream<AppUsageEvent> usageEvents() {
    return _usageEvents.receiveBroadcastStream().map((event) {
      final map = Map<String, dynamic>.from(event as Map);
      return AppUsageEvent(
        packageName: map['packageName'] as String,
        appLabel: (map['appLabel'] as String?) ?? '',
        startedAt: DateTime.fromMillisecondsSinceEpoch(
          map['startedAt'] as int,
        ),
        endedAt: DateTime.fromMillisecondsSinceEpoch(
          map['endedAt'] as int,
        ),
        durationSeconds: map['durationSeconds'] as int,
      );
    });
  }

  Future<bool> prepareVpn() async {
    final ok = await _methods.invokeMethod<bool>('prepareVpn');
    return ok ?? false;
  }

  Future<void> startVpn(List<String> blockedDomains) async {
    await _methods.invokeMethod<void>('startVpn', {
      'blockedDomains': blockedDomains,
    });
  }

  Future<void> stopVpn() async {
    await _methods.invokeMethod<void>('stopVpn');
  }

  Future<bool> requestNotificationPermission() async {
    final granted =
        await _methods.invokeMethod<bool>('requestNotificationPermission');
    return granted ?? false;
  }

  Future<List<PendingDomainEvent>> pendingDomainEvents() async {
    final rows = await _methods.invokeListMethod<Map<Object?, Object?>>(
          'getPendingDomainEvents',
        ) ??
        const [];
    return rows
        .map((row) => PendingDomainEvent(
              rowId: (row['id'] as num).toInt(),
              eventId: row['eventId'] as String,
              domain: row['domain'] as String,
              action: row['action'] as String,
              occurredAt: DateTime.fromMillisecondsSinceEpoch(
                (row['occurredAt'] as num).toInt(),
              ),
            ))
        .toList();
  }

  Future<List<PendingUsageEvent>> pendingUsageEvents() async {
    final rows = await _methods.invokeListMethod<Map<Object?, Object?>>(
          'getPendingUsageEvents',
        ) ??
        const [];
    return rows
        .map((row) => PendingUsageEvent(
              rowId: (row['id'] as num).toInt(),
              eventId: row['eventId'] as String,
              packageName: row['packageName'] as String,
              appLabel: row['appLabel'] as String,
              startedAt: DateTime.fromMillisecondsSinceEpoch(
                (row['startedAt'] as num).toInt(),
              ),
              endedAt: DateTime.fromMillisecondsSinceEpoch(
                (row['endedAt'] as num).toInt(),
              ),
              durationSeconds: (row['durationSeconds'] as num).toInt(),
            ))
        .toList();
  }

  Future<void> acknowledgeDomainEvents(List<int> ids) async {
    await _methods.invokeMethod<void>(
      'acknowledgeDomainEvents',
      {'ids': ids},
    );
  }

  Future<void> acknowledgeUsageEvents(List<int> ids) async {
    await _methods.invokeMethod<void>(
      'acknowledgeUsageEvents',
      {'ids': ids},
    );
  }

  Future<void> updateBlockList(List<String> blockedDomains) async {
    await _methods.invokeMethod<void>('updateBlockList', {
      'blockedDomains': blockedDomains,
    });
  }

  Future<void> updateBlockedApps(List<String> packages) async {
    await _methods.invokeMethod<void>('updateBlockedApps', {
      'packages': packages,
    });
  }

  Future<void> updateDailyAppLimits(Map<String, int> limits) async {
    await _methods.invokeMethod<void>('updateDailyAppLimits', {
      'limits': limits,
    });
  }

  Future<bool> isVpnRunning() async {
    final ok = await _methods.invokeMethod<bool>('isVpnRunning');
    return ok ?? false;
  }

  Future<bool> hasUsagePermission() async {
    final ok = await _methods.invokeMethod<bool>('hasUsagePermission');
    return ok ?? false;
  }

  Future<void> openUsageAccessSettings() async {
    await _methods.invokeMethod<void>('openUsageAccessSettings');
  }

  Future<void> openAppDetailsSettings() async {
    await _methods.invokeMethod<void>('openAppDetailsSettings');
  }

  Future<bool> hasAccessibilityPermission() async {
    final ok = await _methods.invokeMethod<bool>('hasAccessibilityPermission');
    return ok ?? false;
  }

  Future<void> openAccessibilitySettings() async {
    await _methods.invokeMethod<void>('openAccessibilitySettings');
  }
}
