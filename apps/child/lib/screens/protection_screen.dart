import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared/shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../native/protection_bridge.dart';
import '../widgets/child_companion.dart';
import '../widgets/companion_check_in.dart';

class ProtectionScreen extends StatefulWidget {
  const ProtectionScreen({
    super.key,
    this.localeCode = 'en',
    this.onLocaleChanged,
  });

  final String localeCode;
  final ValueChanged<String>? onLocaleChanged;

  @override
  State<ProtectionScreen> createState() => _ProtectionScreenState();
}

class _ProtectionScreenState extends State<ProtectionScreen>
    with WidgetsBindingObserver {
  final _family = FamilyService();
  final _auth = AuthService();
  final _bridge = ProtectionBridge();
  final _protectionCodeController = TextEditingController();

  Profile? _profile;
  Family? _familyModel;
  List<String> _blockedApps = [];
  List<AppTimeLimit> _timeLimits = [];
  List<ExtraTimeRequest> _extraTimeRequests = [];
  List<VpnControlRequest> _vpnRequests = [];
  List<FamilyZone> _zones = [];
  List<ZoneAppRule> _zoneAppRules = [];
  List<ChildTask> _tasks = [];
  List<ChildMoodCheckin> _moodCheckins = [];
  List<ChildTemporaryAppUnlock> _appUnlocks = [];
  ChildStreak? _streak;
  List<AppUsageLog> _activityLogs = [];
  String _protectionMode = 'strict';
  Map<String, int> _dailyUsageSeconds = {};
  Map<String, int> _approvedExtraSeconds = {};
  bool _loading = true;
  bool _vpnOn = false;
  bool _applyingProtectionCode = false;
  bool _sendingCheckIn = false;
  bool _usageOk = false;
  bool _a11yOk = false;
  bool _syncingDomainEvents = false;
  bool _syncingUsageEvents = false;
  bool _locationSharing = false;
  int _selectedSection = 0;
  String _taskFilter = 'all';
  String? _status;
  String? _error;
  Position? _lastPosition;
  Set<String> _activeZoneIds = {};
  final Map<String, DateTime> _offTaskAlerts = {};

  bool get _hindi => widget.localeCode == 'hi';

  String _text(String english, String hindi) => _hindi ? hindi : english;

  StreamSubscription<DomainEvent>? _domainSub;
  StreamSubscription<AppUsageEvent>? _usageSub;
  StreamSubscription<Position>? _locationSubscription;
  Timer? _locationPollTimer;
  RealtimeChannel? _realtimeRulesSub;
  Timer? _syncTimer;
  Timer? _deviceStatusTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermissions();
      if (_locationSharing && _locationSubscription == null) {
        unawaited(_startLocationSharing());
      }
    }
  }

  Future<void> _reportDeviceStatus({
    bool? vpnEnabled,
    bool? usageAccessEnabled,
    bool? accessibilityEnabled,
    bool? locationSharingEnabled,
  }) async {
    final family = _familyModel;
    if (!_family.isUsingSupabase || family == null) return;
    try {
      await _family.reportChildDeviceStatus(
        vpnEnabled: vpnEnabled ?? await _bridge.isVpnRunning(),
        usageAccessEnabled:
            usageAccessEnabled ?? await _bridge.hasUsagePermission(),
        accessibilityEnabled:
            accessibilityEnabled ?? await _bridge.hasAccessibilityPermission(),
        locationSharingEnabled: locationSharingEnabled ?? _locationSharing,
      );
    } catch (e) {
      debugPrint('Reporting child device status failed: $e');
      if (mounted) {
        setState(() => _status = 'Device status could not sync.');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _domainSub?.cancel();
    _usageSub?.cancel();
    _locationSubscription?.cancel();
    _locationPollTimer?.cancel();
    _realtimeRulesSub?.unsubscribe();
    _syncTimer?.cancel();
    _deviceStatusTimer?.cancel();
    _protectionCodeController.dispose();
    super.dispose();
  }

  Future<void> _refreshPermissions() async {
    try {
      final usage = await _bridge.hasUsagePermission();
      final accessibility = await _bridge.hasAccessibilityPermission();
      final vpn = await _bridge.isVpnRunning();
      var shareLocation = _locationSharing;
      final profile = _profile;
      if (shareLocation &&
          await Geolocator.checkPermission() != LocationPermission.always) {
        await _locationSubscription?.cancel();
        _locationSubscription = null;
        _locationPollTimer?.cancel();
        _locationPollTimer = null;
        _activeZoneIds = {};
        shareLocation = false;
        if (profile != null) {
          final preferences = await SharedPreferences.getInstance();
          await preferences.setBool(
            'child_location_sharing_${profile.id}',
            false,
          );
        }
        await _bridge.updateBlockedApps(
          _effectiveBlockedApps(
            _blockedApps,
            _zones,
            _zoneAppRules,
            null,
            _appUnlocks,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _usageOk = usage;
        _a11yOk = accessibility;
        _vpnOn = vpn;
        _locationSharing = shareLocation;
      });
      await _reportDeviceStatus(
        vpnEnabled: vpn,
        usageAccessEnabled: usage,
        accessibilityEnabled: accessibility,
        locationSharingEnabled: shareLocation,
      );
    } catch (e) {
      if (mounted) {
        debugPrint('Checking Android permissions failed: $e');
        setState(() => _status = 'Could not check permissions.');
      }
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _family.reload();
      await _auth.ensureProfile();
      final profile = await _family.fetchMyProfile();
      final family = await _family.fetchMyFamily();
      var shareLocation = false;
      if (_family.isUsingSupabase && profile != null) {
        final preferences = await SharedPreferences.getInstance();
        shareLocation =
            preferences.getBool('child_location_sharing_${profile.id}') ??
                false;
      }
      final vpn = await _bridge.isVpnRunning();
      final usage = await _bridge.hasUsagePermission();
      final a11y = await _bridge.hasAccessibilityPermission();
      List<String> blocked = [];
      List<String> apps = [];
      List<AppUsageLog> activityLogs = [];
      List<AppTimeLimit> timeLimits = [];
      List<ExtraTimeRequest> extraTimeRequests = [];
      List<VpnControlRequest> vpnRequests = [];
      List<FamilyZone> zones = [];
      List<ZoneAppRule> zoneAppRules = [];
      List<ChildTask> tasks = [];
      List<ChildMoodCheckin> moodCheckins = [];
      List<ChildTemporaryAppUnlock> appUnlocks = [];
      ChildStreak? streak;
      Map<String, int> dailyUsage = {};
      Map<String, int> approvedExtraSeconds = {};
      if (family != null) {
        // Fetches effective blocked domains (custom + categories)
        blocked = await _family.fetchChildBlockDomains(
          familyId: family.id,
          childId: profile?.id ?? '',
        );
        apps = await _family.fetchChildBlockedAppPackages(
          familyId: family.id,
          childId: profile?.id ?? '',
        );
        if (_family.isUsingSupabase && profile != null) {
          activityLogs = await _family.fetchAppUsageLogs(
            familyId: family.id,
            childId: profile.id,
            limit: 700,
          );
          timeLimits = await _family.fetchAppTimeLimits(
            familyId: family.id,
            childId: profile.id,
          );
          dailyUsage = await _loadDailyUsage(family, profile.id);
          extraTimeRequests = await _family.fetchExtraTimeRequests(
            familyId: family.id,
            childId: profile.id,
          );
          vpnRequests = await _family.fetchVpnControlRequests(
            familyId: family.id,
            childId: profile.id,
          );
          zones = await _family.fetchFamilyZones(family.id);
          zoneAppRules = await _family.fetchZoneAppRules(family.id);
          tasks = await _family.fetchChildTasks(
            familyId: family.id,
            childId: profile.id,
          );
          moodCheckins = await _family.fetchChildMoodCheckins(
            familyId: family.id,
            childId: profile.id,
          );
          streak = await _family.fetchChildStreak(profile.id);
          appUnlocks = await _family.fetchActiveChildAppUnlocks(profile.id);
          _protectionMode = await _family.fetchChildProtectionMode(
            familyId: family.id,
            childId: profile.id,
          );
          approvedExtraSeconds = _approvedExtraTime(extraTimeRequests);
        }
        await _bridge.updateBlockList(blocked);
        await _bridge.updateBlockedApps(
          _effectiveBlockedApps(
              apps, zones, zoneAppRules, _lastPosition, appUnlocks),
        );
        await _bridge.updateDailyAppLimits(
          _effectiveDailyLimits(timeLimits, approvedExtraSeconds),
        );

        // Subscribe to real-time rule changes from parent
        _realtimeRulesSub?.unsubscribe();
        _realtimeRulesSub = _family.subscribeToRules(family.id, () {
          _syncRules();
        });
      }

      setState(() {
        _profile = profile;
        _familyModel = family;
        _blockedApps = apps;
        _activityLogs = activityLogs;
        _timeLimits = timeLimits;
        _extraTimeRequests = extraTimeRequests;
        _vpnRequests = vpnRequests;
        _zones = zones;
        _zoneAppRules = zoneAppRules;
        _tasks = tasks;
        _moodCheckins = moodCheckins;
        _appUnlocks = appUnlocks;
        _streak = streak;
        _dailyUsageSeconds = dailyUsage;
        _approvedExtraSeconds = approvedExtraSeconds;
        _vpnOn = vpn;
        _usageOk = usage;
        _a11yOk = a11y;
        _locationSharing = shareLocation;
        _loading = false;
      });

      _domainSub ??= _bridge.domainEvents().listen(_onDomainEvent);
      _usageSub ??= _bridge.usageEvents().listen(_onUsageEvent);
      unawaited(_flushPendingDomainEvents());
      unawaited(_flushPendingUsageEvents());
      unawaited(_reportDeviceStatus(
        vpnEnabled: vpn,
        usageAccessEnabled: usage,
        accessibilityEnabled: a11y,
        locationSharingEnabled: shareLocation,
      ));
      _deviceStatusTimer ??= Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(_reportDeviceStatus()),
      );
      if (shareLocation && family != null) {
        await _startLocationSharing();
      }
      _syncTimer ??= Timer.periodic(
        const Duration(seconds: 20),
        (_) => _syncRules(),
      );
    } catch (e) {
      debugPrint('Loading child protection settings failed: $e');
      setState(() {
        _error = 'Error. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _syncRules() async {
    final family = _familyModel;
    if (family == null) return;
    try {
      await _family.reload();
      final profile = _profile;
      final blocked = await _family.fetchChildBlockDomains(
        familyId: family.id,
        childId: profile?.id ?? '',
      );
      final apps = await _family.fetchChildBlockedAppPackages(
        familyId: family.id,
        childId: profile?.id ?? '',
      );
      var limits = _timeLimits;
      var activityLogs = _activityLogs;
      var dailyUsage = _dailyUsageSeconds;
      var extraSeconds = _approvedExtraSeconds;
      var extraRequests = _extraTimeRequests;
      var vpnRequests = _vpnRequests;
      var zones = _zones;
      var zoneAppRules = _zoneAppRules;
      var tasks = _tasks;
      var moodCheckins = _moodCheckins;
      var appUnlocks = _appUnlocks;
      var streak = _streak;
      var protectionMode = _protectionMode;
      if (_family.isUsingSupabase && profile != null) {
        activityLogs = await _family.fetchAppUsageLogs(
          familyId: family.id,
          childId: profile.id,
          limit: 700,
        );
        limits = await _family.fetchAppTimeLimits(
          familyId: family.id,
          childId: profile.id,
        );
        dailyUsage = await _loadDailyUsage(family, profile.id);
        extraRequests = await _family.fetchExtraTimeRequests(
          familyId: family.id,
          childId: profile.id,
        );
        protectionMode = await _family.fetchChildProtectionMode(
          familyId: family.id,
          childId: profile.id,
        );
        vpnRequests = await _family.fetchVpnControlRequests(
          familyId: family.id,
          childId: profile.id,
        );
        zones = await _family.fetchFamilyZones(family.id);
        zoneAppRules = await _family.fetchZoneAppRules(family.id);
        tasks = await _family.fetchChildTasks(
          familyId: family.id,
          childId: profile.id,
        );
        moodCheckins = await _family.fetchChildMoodCheckins(
          familyId: family.id,
          childId: profile.id,
        );
        streak = await _family.fetchChildStreak(profile.id);
        appUnlocks = await _family.fetchActiveChildAppUnlocks(profile.id);
        extraSeconds = _approvedExtraTime(extraRequests);
      }
      await _bridge.updateBlockList(blocked);
      await _bridge.updateDailyAppLimits(
        _effectiveDailyLimits(limits, extraSeconds),
      );
      await _bridge.updateBlockedApps(
        _effectiveBlockedApps(
          apps,
          zones,
          zoneAppRules,
          _lastPosition,
          appUnlocks,
        ),
      );
      if (mounted) {
        setState(() {
          _blockedApps = apps;
          _activityLogs = activityLogs;
          _timeLimits = limits;
          _extraTimeRequests = extraRequests;
          _vpnRequests = vpnRequests;
          _zones = zones;
          _zoneAppRules = zoneAppRules;
          _tasks = tasks;
          _moodCheckins = moodCheckins;
          _appUnlocks = appUnlocks;
          _streak = streak;
          _protectionMode = protectionMode;
          _dailyUsageSeconds = dailyUsage;
          _approvedExtraSeconds = extraSeconds;
        });
      }
      unawaited(_flushPendingDomainEvents());
      unawaited(_flushPendingUsageEvents());
    } catch (e) {
      if (mounted) {
        debugPrint('Syncing child protection settings failed: $e');
        setState(() => _error = 'Error. Please try again.');
      }
    }
  }

  Future<Map<String, int>> _loadDailyUsage(
    Family family,
    String childId,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final logs = await _family.fetchAppUsageLogs(
      familyId: family.id,
      childId: childId,
      limit: 1000,
    );
    final usage = <String, int>{};
    for (final log in logs) {
      if (log.startedAt.toLocal().isBefore(today)) continue;
      final seconds = log.durationSeconds ?? 0;
      usage.update(
        log.packageName,
        (total) => total + seconds,
        ifAbsent: () => seconds,
      );
    }
    return usage;
  }

  Future<void> _setLocationSharing(bool enabled) async {
    final profile = _profile;
    final family = _familyModel;
    if (profile == null || family == null || !_family.isUsingSupabase) {
      if (mounted) {
        setState(() => _status = 'Location sharing requires a linked account.');
      }
      return;
    }
    if (!enabled) {
      await _locationSubscription?.cancel();
      _locationSubscription = null;
      _locationPollTimer?.cancel();
      _locationPollTimer = null;
      _activeZoneIds = {};
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(
        'child_location_sharing_${profile.id}',
        false,
      );
      if (mounted) setState(() => _locationSharing = false);
      unawaited(_reportDeviceStatus(locationSharingEnabled: false));
      await _bridge.updateBlockedApps(
        _effectiveBlockedApps(
          _blockedApps,
          const [],
          const [],
          null,
          _appUnlocks,
        ),
      );
      return;
    }

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception(
            'Turn on Location in Android settings, then try again.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.always) {
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Allow background location'),
              content: const Text(
                'To send updates and apply school/tuition rules while Family Guard is in the background, set Location permission to "Allow all the time" in Android app settings. Sharing remains off until you enable it.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Not now'),
                ),
                FilledButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await Geolocator.openAppSettings();
                  },
                  child: const Text('Open app settings'),
                ),
              ],
            ),
          );
        }
        return;
      }
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(
        'child_location_sharing_${profile.id}',
        true,
      );
      if (mounted) setState(() => _locationSharing = true);
      unawaited(_reportDeviceStatus(locationSharingEnabled: true));
      await _startLocationSharing();
    } catch (error) {
      debugPrint('Starting child location sharing failed: $error');
      if (mounted) {
        setState(() => _status = 'Location could not start. Please try again.');
      }
    }
  }

  Future<void> _startLocationSharing() async {
    if (_locationSubscription != null) return;
    final profile = _profile;
    if (profile == null || !_locationSharing) return;
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always) {
      if (mounted) {
        setState(() {
          _locationSharing = false;
          _status = 'Allow location access all the time to share updates.';
        });
      }
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(
        'child_location_sharing_${profile.id}',
        false,
      );
      unawaited(_reportDeviceStatus(locationSharingEnabled: false));
      return;
    }
    final locationSettings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 30,
            intervalDuration: const Duration(seconds: 30),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'Family Guard location sharing is on',
              notificationText:
                  'Your parent can see your location and zone protections are active.',
              enableWakeLock: true,
            ),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 30,
          );
    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (position) {
        _lastPosition = position;
        unawaited(_processLocation(position));
      },
      onError: (Object error) {
        debugPrint('Child location stream failed: $error');
        if (mounted) {
          setState(
            () => _status = 'Location updates paused. Check device settings.',
          );
        }
      },
    );
    _locationPollTimer?.cancel();
    _locationPollTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => unawaited(_sampleCurrentLocation(locationSettings)),
    );
    await _sampleCurrentLocation(locationSettings);
  }

  Future<void> _sampleCurrentLocation(LocationSettings settings) async {
    if (!_locationSharing) return;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: settings,
      );
      if (!_locationSharing) return;
      _lastPosition = position;
      await _processLocation(position);
    } catch (error) {
      debugPrint('Getting child location failed: $error');
      if (mounted) {
        setState(
            () => _status = 'Could not update location. Please try again.');
      }
    }
  }

  Set<String> _zonesForPosition(Position position, List<FamilyZone> zones) {
    return {
      for (final zone in zones)
        if (Geolocator.distanceBetween(
              position.latitude,
              position.longitude,
              zone.latitude,
              zone.longitude,
            ) <=
            zone.radiusMeters)
          zone.id,
    };
  }

  List<String> _effectiveBlockedApps(
    List<String> baseApps,
    List<FamilyZone> zones,
    List<ZoneAppRule> rules,
    Position? position,
    List<ChildTemporaryAppUnlock> appUnlocks,
  ) {
    final now = DateTime.now();
    final unlockedPackages = appUnlocks
        .where((unlock) => unlock.expiresAt.isAfter(now))
        .map((unlock) => unlock.packageName)
        .toSet();
    final filteredBaseApps = baseApps
        .where((packageName) => !unlockedPackages.contains(packageName));
    if (!_locationSharing || position == null) return filteredBaseApps.toList();
    final activeZones = _zonesForPosition(position, zones);
    return {
      ...filteredBaseApps,
      for (final rule in rules)
        if (activeZones.contains(rule.zoneId)) rule.packageName,
    }.where((packageName) => !unlockedPackages.contains(packageName)).toList();
  }

  Future<void> _processLocation(Position position) async {
    final family = _familyModel;
    final profile = _profile;
    if (!_locationSharing || family == null || profile == null) return;
    try {
      await _family.recordChildLocation(
        familyId: family.id,
        childId: profile.id,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
      );
      final activeZones = _zonesForPosition(position, _zones);
      final previousZones = _activeZoneIds;
      _activeZoneIds = activeZones;
      for (final zoneId in activeZones.difference(previousZones)) {
        final eventId = await _family.recordZoneEvent(
          familyId: family.id,
          childId: profile.id,
          zoneId: zoneId,
          eventType: 'entered',
        );
        await _notifyParentZoneEvent(eventId);
      }
      for (final zoneId in previousZones.difference(activeZones)) {
        final eventId = await _family.recordZoneEvent(
          familyId: family.id,
          childId: profile.id,
          zoneId: zoneId,
          eventType: 'exited',
        );
        await _notifyParentZoneEvent(eventId);
      }
      await _bridge.updateBlockedApps(
        _effectiveBlockedApps(
          _blockedApps,
          _zones,
          _zoneAppRules,
          position,
          _appUnlocks,
        ),
      );
    } catch (error) {
      debugPrint('Syncing child location or zone activity failed: $error');
      if (mounted) {
        setState(
          () => _status = 'Location could not sync. Please try again.',
        );
      }
    }
  }

  Future<void> _notifyParentZoneEvent(String eventId) async {
    try {
      await _family.sendParentZoneAlert(eventId);
    } catch (error) {
      debugPrint('Sending parent location alert failed: $error');
    }
  }

  Future<void> _submitTaskProof(ChildTask task) async {
    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 75,
        maxWidth: 1600,
      );
      if (photo == null) return;
      final family = _familyModel;
      if (family == null) {
        throw Exception('Link to a parent family before submitting a task.');
      }
      final bytes = await photo.readAsBytes();
      await _family.submitChildTask(
        taskId: task.id,
        photoBytes: Uint8List.fromList(bytes),
        note: '',
      );
      await _syncRules();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo proof sent to your parent.')),
        );
      }
    } catch (error) {
      debugPrint('Submitting child task proof failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error. Please try again.')),
        );
      }
    }
  }

  Future<void> _showMoodCheckinDialog() async {
    final profile = _profile;
    final family = _familyModel;
    if (_sendingCheckIn) return;
    if (profile == null || family == null || !_family.isUsingSupabase) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_text(
              'Connect your family account to share a check-in.',
              'चेक-इन भेजने के लिए पारिवारिक खाता जोड़ें।'))));
      return;
    }
    _sendingCheckIn = true;
    try {
      final response = await showDialog<CompanionCheckIn>(
          context: context,
          builder: (_) => CompanionCheckInDialog(hindi: _hindi));
      if (response == null) return;
      await _family.createChildMoodCheckin(
          familyId: family.id,
          childId: profile.id,
          mood: response.mood,
          note: response.note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_text('Your check-in was shared with your parent.',
              'आपका चेक-इन माता-पिता को भेज दिया गया है।'))));
      await _syncRules();
    } catch (error) {
      debugPrint('Sending child check-in failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_text('Check-in could not be sent. Please try again.',
                'चेक-इन नहीं भेजा जा सका। फिर कोशिश करें।'))));
      }
    } finally {
      _sendingCheckIn = false;
    }
  }

  bool get _moodCheckinDue => !_moodCheckins.any((checkIn) =>
      DateUtils.isSameDay(checkIn.createdAt.toLocal(), DateTime.now()));

  Map<String, int> _effectiveDailyLimits(
    List<AppTimeLimit> limits,
    Map<String, int> approvedExtraSeconds,
  ) {
    return {
      for (final limit in limits)
        limit.packageName: limit.dailyLimitSeconds +
            (approvedExtraSeconds[limit.packageName] ?? 0),
    };
  }

  Map<String, int> _approvedExtraTime(List<ExtraTimeRequest> requests) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final seconds = <String, int>{};
    for (final request in requests) {
      final resolvedAt = request.resolvedAt?.toLocal();
      final grantedMinutes = request.grantedMinutes;
      if (request.status != 'approved' ||
          resolvedAt == null ||
          resolvedAt.isBefore(today) ||
          grantedMinutes == null) {
        continue;
      }
      seconds.update(
        request.packageName,
        (total) => total + grantedMinutes * 60,
        ifAbsent: () => grantedMinutes * 60,
      );
    }
    return seconds;
  }

  Future<void> _onDomainEvent(DomainEvent event) async {
    unawaited(_flushPendingDomainEvents());
  }

  Future<void> _flushPendingDomainEvents() async {
    if (_syncingDomainEvents) return;
    final family = _familyModel;
    final profile = _profile;
    if (family == null || profile == null) return;
    _syncingDomainEvents = true;
    try {
      var events = await _bridge.pendingDomainEvents();
      while (events.isNotEmpty) {
        for (final event in events) {
          await _family.insertDomainLog(
            familyId: family.id,
            domain: event.domain,
            action: event.action,
            id: event.eventId,
            childId: profile.id,
            occurredAt: event.occurredAt,
          );
          await _bridge.acknowledgeDomainEvents([event.rowId]);
          if (mounted) {
            setState(
              () => _status = 'A website was blocked by your family settings.',
            );
          }
        }
        events = await _bridge.pendingDomainEvents();
      }
    } catch (e) {
      if (mounted) {
        debugPrint('Syncing child network activity failed: $e');
        setState(() => _status = 'Some activity is waiting to sync.');
      }
    } finally {
      _syncingDomainEvents = false;
    }
  }

  Future<void> _onUsageEvent(AppUsageEvent event) async {
    final family = _familyModel;
    final profile = _profile;
    if (family != null && profile != null && _activeZoneIds.isNotEmpty) {
      final matchingRule = _zoneAppRules
          .where(
            (rule) =>
                rule.packageName == event.packageName &&
                _activeZoneIds.contains(rule.zoneId),
          )
          .firstOrNull;
      if (matchingRule != null) {
        final alertKey = '${matchingRule.zoneId}:${event.packageName}';
        final lastAlert = _offTaskAlerts[alertKey];
        final now = DateTime.now();
        if (lastAlert == null ||
            now.difference(lastAlert) >= const Duration(minutes: 10)) {
          _offTaskAlerts[alertKey] = now;
          unawaited(_reportOffTaskEvent(
            familyId: family.id,
            childId: profile.id,
            zoneId: matchingRule.zoneId,
            packageName: event.packageName,
          ));
        }
      }
    }
    unawaited(_flushPendingUsageEvents());
  }

  Future<void> _reportOffTaskEvent({
    required String familyId,
    required String childId,
    required String zoneId,
    required String packageName,
  }) async {
    late final String eventId;
    try {
      eventId = await _family.recordZoneEvent(
        familyId: familyId,
        childId: childId,
        zoneId: zoneId,
        eventType: 'off_task_app',
        packageName: packageName,
      );
    } catch (error) {
      debugPrint('Reporting child zone event failed: $error');
      if (mounted) {
        setState(() => _status = 'Location activity could not sync.');
      }
      return;
    }
    try {
      await _family.sendParentZoneAlert(eventId);
    } catch (error) {
      debugPrint('Sending parent zone alert failed: $error');
      if (mounted) {
        setState(
          () => _status =
              'Location activity was recorded, but the parent could not be notified.',
        );
      }
    }
  }

  Future<void> _flushPendingUsageEvents() async {
    if (_syncingUsageEvents) return;
    final family = _familyModel;
    final profile = _profile;
    if (family == null || profile == null) return;
    _syncingUsageEvents = true;
    try {
      var events = await _bridge.pendingUsageEvents();
      var hadEvents = false;
      while (events.isNotEmpty) {
        for (final event in events) {
          hadEvents = true;
          await _family.insertAppUsageLog(
            familyId: family.id,
            packageName: event.packageName,
            appLabel: event.appLabel,
            startedAt: event.startedAt,
            id: event.eventId,
            endedAt: event.endedAt,
            durationSeconds: event.durationSeconds,
            childId: profile.id,
          );
          await _bridge.acknowledgeUsageEvents([event.rowId]);
        }
        events = await _bridge.pendingUsageEvents();
      }
      if (hadEvents) {
        final usage = await _loadDailyUsage(family, profile.id);
        if (mounted) setState(() => _dailyUsageSeconds = usage);
      }
    } catch (e) {
      if (mounted) {
        debugPrint('Syncing child app activity failed: $e');
        setState(() => _status = 'Some app activity is waiting to sync.');
      }
    } finally {
      _syncingUsageEvents = false;
    }
  }

  Future<void> _requestExtraTime(AppTimeLimit limit) async {
    final controller = TextEditingController(text: '30');
    final minutes = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Request extra time for '
          '${limit.appLabel.isEmpty ? limit.packageName : limit.appLabel}',
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Minutes requested'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    controller.dispose();
    final family = _familyModel;
    final profile = _profile;
    if (minutes == null || minutes <= 0 || family == null || profile == null) {
      return;
    }
    try {
      final status = await _family.createExtraTimeRequest(
        familyId: family.id,
        childId: profile.id,
        packageName: limit.packageName,
        appLabel: limit.appLabel,
        requestedMinutes: minutes,
      );
      await _syncRules();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == 'approved'
                  ? 'Extra time approved automatically based on your trust score.'
                  : 'Extra-time request sent to your parent.',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Sending child extra-time request failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error. Please try again.')),
        );
      }
    }
  }

  Future<void> _redeemTemporaryAppUnlock(String packageName) async {
    final family = _familyModel;
    if (family == null) return;
    try {
      final unlock = await _family.redeemChildTemporaryAppUnlock(
        familyId: family.id,
        packageName: packageName,
      );
      await _syncRules();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${unlock.packageName} unlocked for 15 minutes.',
            ),
          ),
        );
      }
    } catch (error) {
      debugPrint('Using child app unlock failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error. Please try again.')),
        );
      }
    }
  }

  Future<void> _requestProtectionPause() async {
    final family = _familyModel;
    final profile = _profile;
    if (_protectionMode != 'friendly' ||
        family == null ||
        profile == null ||
        !_family.isUsingSupabase) {
      return;
    }
    if (_vpnRequests.any((request) => request.status == 'pending')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your parent already has a pending pause request.'),
        ),
      );
      return;
    }
    try {
      await _family.createVpnControlRequest(
        familyId: family.id,
        childId: profile.id,
      );
      await _syncRules();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Pause request sent. If your parent approves, ask them for a one-time OFF code.',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Sending child VPN pause request failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error. Please try again.')),
        );
      }
    }
  }

  Future<void> _showProtectionCodeDialog() async {
    _protectionCodeController.clear();
    final shouldApply = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Parent approval'),
        content: TextField(
          controller: _protectionCodeController,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          maxLength: 8,
          decoration: const InputDecoration(
            labelText: 'One-time parent code',
            hintText: 'Enter the code your parent gave you',
            counterText: '',
            prefixIcon: LiveIcon(Icons.key_outlined),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (shouldApply == true) await _applyProtectionCode();
  }

  Future<void> _applyProtectionCode() async {
    final code = _protectionCodeController.text.trim().toUpperCase();
    if (!RegExp(r'^[0-9A-F]{8}$').hasMatch(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the 8-character parent code.')),
      );
      return;
    }

    final requestedAction = _vpnOn ? 'disable' : 'enable';
    setState(() => _applyingProtectionCode = true);
    try {
      if (requestedAction == 'enable') {
        final prepared = await _bridge.prepareVpn();
        if (!prepared) {
          throw Exception('VPN permission is required to enable protection.');
        }
      }

      final acceptedAction = await _family.redeemProtectionControlCode(
        code: code,
        requestedAction: requestedAction,
      );
      if (acceptedAction == 'enable') {
        final notificationsGranted =
            await _bridge.requestNotificationPermission();
        if (!notificationsGranted && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Enable notifications so Android can keep the protection service visible.',
              ),
            ),
          );
        }
        final family = _familyModel;
        if (family == null) {
          throw Exception('Link this Child app to a parent family first.');
        }
        final domains = await _family.fetchChildBlockDomains(
          familyId: family.id,
          childId: _profile?.id ?? '',
        );
        await _bridge.updateBlockList(domains);
        await _bridge.startVpn(domains);
      } else {
        await _bridge.stopVpn();
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final running = await _bridge.isVpnRunning();
      if (running != (acceptedAction == 'enable')) {
        throw Exception('Android could not apply the protection change.');
      }
      _protectionCodeController.clear();
      if (mounted) {
        setState(() {
          _vpnOn = running;
          _status = running ? 'Protection enabled by parent code.' : null;
        });
      }
      unawaited(_reportDeviceStatus(vpnEnabled: running));
    } catch (error) {
      debugPrint('Applying parent protection code failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update protection. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _applyingProtectionCode = false);
    }
  }

  Future<void> _requestUsage() async {
    await _bridge.openUsageAccessSettings();
  }

  Future<void> _requestA11y() async {
    await _bridge.openAccessibilitySettings();
  }

  Future<void> _showPermissionHelp({
    required String permissionName,
    required Future<void> Function() openPermissionSettings,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Enable $permissionName'),
        content: const Text(
          'On Android 13 and newer, sideloaded apps may be blocked from using restricted settings. First open Family Guard Child app info, tap the three-dot menu, and choose “Allow restricted settings”. Return here, then open the permission settings and enable Family Guard Child. Android requires this manual approval; the app cannot grant it itself.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _bridge.openAppDetailsSettings();
            },
            child: const Text('Open app info'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await openPermissionSettings();
            },
            child: const Text('Open permission settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildUnlinkedMessage() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LiveIcon(Icons.family_restroom, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'You’re not linked yet',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Ask your parent to create your child account. Once they add it, sign out and sign back in here.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _auth.signOut(),
                    icon: const LiveIcon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  void _openActivityLogs() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.88,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _text('My Activity & Screen Logs',
                          'मेरी गतिविधि और स्क्रीन लॉग'),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const LiveIcon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CategorizedLogsView(
                  deviceStatus: _profile == null || _familyModel == null
                      ? null
                      : ChildDeviceStatus(
                          childId: _profile!.id,
                          familyId: _familyModel!.id,
                          vpnEnabled: _vpnOn,
                          usageAccessEnabled: _usageOk,
                          accessibilityEnabled: _a11yOk,
                          lastSeenAt: DateTime.now()),
                  appLogs: _activityLogs,
                  childName: _profile?.displayName ?? 'Child',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeHeader(BuildContext context) => GlassCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            LiveIcon(_vpnOn ? Icons.shield_rounded : Icons.gpp_bad_rounded,
                size: 60, color: _vpnOn ? AppPalette.blue : AppPalette.red),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${_text('Hi', 'नमस्ते')} ${_profile?.displayName ?? _text('there', 'दोस्त')}!',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 8),
                      LivePulseBadge(
                        label: _vpnOn ? 'PROTECTED' : 'ATTENTION',
                        color: _vpnOn
                            ? const Color(0xFF2563EB)
                            : const Color(0xFFDC3545),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(_vpnOn
                      ? _text('Protection is on. Your device is connected.',
                          'एजिस आपके डिवाइस की रक्षा कर रहा है। आपका दिन शुभ हो!')
                      : _text('Protection needs your parent’s attention.',
                          'सुरक्षा के लिए अपने माता-पिता से संपर्क करें।')),
                ],
              ),
            ),
          ],
        ),
      );

  String _taskStatusLabel(String status) => switch (status) {
        'submitted' => 'Sent for review',
        'approved' => 'Completed',
        'rejected' => 'Needs another try',
        _ => 'To do',
      };

  Widget _buildChildTasks() {
    final visible = _tasks
        .where((task) => _taskFilter == 'all' || task.taskType == _taskFilter)
        .toList()
      ..sort((a, b) {
        final aDate = (a.dueAt ?? a.createdAt).toLocal();
        final bDate = (b.dueAt ?? b.createdAt).toLocal();
        return aDate.compareTo(bDate);
      });
    final grouped = <DateTime, List<ChildTask>>{};
    for (final task in visible) {
      final date = (task.dueAt ?? task.createdAt).toLocal();
      grouped
          .putIfAbsent(DateTime(date.year, date.month, date.day), () => [])
          .add(task);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_streak != null)
          Card(
            child: ListTile(
              leading: const LiveIcon(Icons.local_fire_department_outlined),
              title: Text('${_streak!.currentStreak}-day task streak'),
              subtitle: Text('${_streak!.totalPoints} points earned so far'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Wrap(
            spacing: 8,
            children: [
              for (final filter in const ['all', 'task', 'homework'])
                ChoiceChip(
                  label: Text(switch (filter) {
                    'task' => 'Tasks',
                    'homework' => 'Homework',
                    _ => 'All',
                  }),
                  selected: _taskFilter == filter,
                  onSelected: (_) => setState(() => _taskFilter = filter),
                ),
            ],
          ),
        ),
        if (visible.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No work here yet. Enjoy your free time!'),
              ),
            ),
          )
        else
          for (final entry in grouped.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
              child: Text(
                DateUtils.isSameDay(entry.key, DateTime.now())
                    ? 'Today'
                    : DateFormat('EEEE, MMM d').format(entry.key),
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            for (final task in entry.value)
              Card(
                child: ListTile(
                  leading: LiveIcon(
                    task.taskType == 'homework'
                        ? Icons.menu_book_outlined
                        : Icons.task_alt_rounded,
                  ),
                  title: Text(task.title),
                  subtitle: Text(
                    '${task.description.isEmpty ? '' : '${task.description}\n'}${task.taskType == 'homework' ? 'Homework' : 'Task'} · ${_taskStatusLabel(task.status)}',
                  ),
                  isThreeLine: task.description.isNotEmpty,
                  trailing:
                      task.status == 'assigned' || task.status == 'rejected'
                          ? IconButton.filledTonal(
                              tooltip: 'Send photo proof',
                              onPressed: () => _submitTaskProof(task),
                              icon: const LiveIcon(Icons.camera_alt_outlined),
                            )
                          : const LiveIcon(Icons.check_circle_outline),
                ),
              ),
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppPalette.navy,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.white,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
            systemNavigationBarColor: Colors.white,
            systemNavigationBarIconBrightness: Brightness.dark),
        title: Text([
          _text('Home', 'होम'),
          _text('My tasks', 'मेरे काम'),
          _text('Focus', 'फ़ोकस'),
          _text('My profile', 'मेरी प्रोफ़ाइल'),
        ][_selectedSection]),
        actions: [
          IconButton(
            tooltip: _text('Refresh', 'रीफ़्रेश'),
            onPressed: _loading ? null : _syncRules,
            icon: const LiveIcon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: _text('Language', 'भाषा'),
            initialValue: widget.localeCode,
            onSelected: widget.onLocaleChanged,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'en', child: Text('English')),
              PopupMenuItem(value: 'hi', child: Text('हिन्दी')),
            ],
            icon: const LiveIcon(Icons.language),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedSection,
        onDestinationSelected: (index) =>
            setState(() => _selectedSection = index),
        destinations: [
          NavigationDestination(
            icon: const LiveIcon(Icons.home_outlined),
            selectedIcon: const LiveIcon(Icons.home_rounded),
            label: _text('Home', 'होम'),
          ),
          NavigationDestination(
            icon: const LiveIcon(Icons.assignment_outlined),
            selectedIcon: const LiveIcon(Icons.assignment_rounded),
            label: _text('My tasks', 'मेरे काम'),
          ),
          NavigationDestination(
            icon: const LiveIcon(Icons.shield_outlined),
            selectedIcon: const LiveIcon(Icons.shield_rounded),
            label: _text('Focus', 'फ़ोकस'),
          ),
          NavigationDestination(
            icon: const LiveIcon(Icons.person_outline),
            selectedIcon: const LiveIcon(Icons.person_rounded),
            label: _text('Profile', 'प्रोफ़ाइल'),
          ),
        ],
      ),
      body: _loading
          ? AppLoadingView(
              message: _text(
                  'Loading your protection', 'आपकी सुरक्षा लोड हो रही है'),
              detail: _text('Getting your latest settings.',
                  'आपकी नवीनतम सेटिंग मिल रही हैं।'))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const LiveIcon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _bootstrap,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : CompanionBackdrop(
                  child: _familyModel == null && _selectedSection != 0
                      ? _buildUnlinkedMessage()
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            if (_status != null)
                              Card(
                                child: ListTile(
                                  leading: const LiveIcon(
                                    Icons.info_outline,
                                    color: Color(0xFF172B4D),
                                  ),
                                  title: Text(_status!),
                                  trailing: IconButton(
                                    tooltip: 'Dismiss',
                                    onPressed: () =>
                                        setState(() => _status = null),
                                    icon: const LiveIcon(Icons.close),
                                  ),
                                ),
                              ),
                            if (_selectedSection == 0) ...[
                              _buildHomeHeader(context),
                              if (_selectedSection == 0 && _profile != null)
                                ChildCompanionCard(
                                    key: ValueKey('companion_${_profile!.id}'),
                                    childId: _profile!.id,
                                    tasks: _tasks,
                                    vpnEnabled: _vpnOn,
                                    permissionsReady: _usageOk && _a11yOk,
                                    checkInDue: _moodCheckinDue,
                                    onTasks: () =>
                                        setState(() => _selectedSection = 1),
                                    onProtection: () =>
                                        setState(() => _selectedSection = 2),
                                    onPermissions: () =>
                                        setState(() => _selectedSection = 3),
                                    onCheckIn: _showMoodCheckinDialog,
                                    hindi: _hindi),
                              const SizedBox(height: 12),
                              if (_familyModel == null)
                                Card(
                                  child: ListTile(
                                    leading: const LiveIcon(Icons.link_off),
                                    title: Text(_text(
                                      'Your account is not linked yet',
                                      'आपका खाता अभी लिंक नहीं है',
                                    )),
                                    subtitle: Text(_text(
                                      'Ask your parent to link your account to sync app activity and family rules.',
                                      'ऐप गतिविधि और परिवार के नियम सिंक करने के लिए अपने माता-पिता से खाता लिंक करने को कहें।',
                                    )),
                                  ),
                                ),
                              GlassCard(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Center(
                                      child: TextButton.icon(
                                        onPressed: _openActivityLogs,
                                        icon: const LiveIcon(
                                            Icons.list_alt_rounded,
                                            size: 18),
                                        label: Text(
                                          _text('View activity and usage graph',
                                              'विस्तृत लॉग देखें (लाइव और उपयोग)'),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            if (_selectedSection == 0) ...[
                              GlassCard(
                                child: SwitchListTile(
                                  secondary: const LiveIcon(
                                      Icons.location_on_outlined),
                                  title: const Text('Share my location'),
                                  subtitle: Text(
                                    _locationSharing
                                        ? 'Your parent can see your latest location.'
                                        : 'Turn this on if you want your parent to know when you arrive at saved places.',
                                  ),
                                  value: _locationSharing,
                                  onChanged: _family.isUsingSupabase
                                      ? _setLocationSharing
                                      : null,
                                ),
                              ),
                              if (_zones.isNotEmpty)
                                Card(
                                  child: ListTile(
                                    leading:
                                        const LiveIcon(Icons.place_outlined),
                                    title: Text(
                                      _activeZoneIds.isEmpty
                                          ? 'No active family zone'
                                          : 'Inside ${_zones.where((zone) => _activeZoneIds.contains(zone.id)).map((zone) => zone.name).join(', ')}',
                                    ),
                                    subtitle: Text(
                                      '${_zones.length} zone${_zones.length == 1 ? '' : 's'} configured · app restrictions apply while location sharing is active.',
                                    ),
                                  ),
                                ),
                            ],
                            if (_selectedSection == 3) ...[
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 28,
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: .12),
                                        child: LiveIcon(
                                          Icons.person_rounded,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          size: 30,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _profile?.displayName ??
                                                  'Your profile',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                            ),
                                            if (_profile?.email.isNotEmpty ==
                                                true)
                                              Text(_profile!.email),
                                            Text(
                                              _familyModel?.name ??
                                                  'Family account',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Card(
                                child: Column(
                                  children: [
                                    ListTile(
                                      leading: LiveIcon(
                                        _usageOk
                                            ? Icons.check_circle_outline
                                            : Icons.info_outline,
                                      ),
                                      title: const Text('Usage tracking'),
                                      subtitle: Text(
                                        _usageOk
                                            ? 'Ready'
                                            : 'Allow Usage access to measure your app activity.',
                                      ),
                                      trailing: _usageOk
                                          ? null
                                          : TextButton(
                                              onPressed: () =>
                                                  _showPermissionHelp(
                                                permissionName: 'Usage access',
                                                openPermissionSettings:
                                                    _requestUsage,
                                              ),
                                              child: const Text('Set up'),
                                            ),
                                    ),
                                    const Divider(height: 1),
                                    ListTile(
                                      leading: LiveIcon(
                                        _a11yOk
                                            ? Icons.check_circle_outline
                                            : Icons.info_outline,
                                      ),
                                      title: const Text('App protections'),
                                      subtitle: Text(
                                        _a11yOk
                                            ? 'Ready'
                                            : 'Enable the service so family rules can work.',
                                      ),
                                      trailing: _a11yOk
                                          ? null
                                          : TextButton(
                                              onPressed: () =>
                                                  _showPermissionHelp(
                                                permissionName: 'Accessibility',
                                                openPermissionSettings:
                                                    _requestA11y,
                                              ),
                                              child: const Text('Set up'),
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                              Card(
                                child: ListTile(
                                  leading: const LiveIcon(Icons.logout),
                                  title: const Text('Sign out'),
                                  subtitle: const Text(
                                    'Your parent can help if you need to sign back in.',
                                  ),
                                  onTap: () => _auth.signOut(),
                                ),
                              ),
                            ],
                            if (_selectedSection == 2) ...[
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          LiveIcon(
                                            _vpnOn
                                                ? Icons.shield
                                                : Icons.shield_outlined,
                                            color: _vpnOn
                                                ? Colors.blue.shade800
                                                : Colors.grey.shade600,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              _vpnOn
                                                  ? 'Protection Active (VPN ON)'
                                                  : 'Protection Paused (VPN OFF)',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _vpnOn
                                            ? 'Your online protection is on. A parent must approve any change.'
                                            : 'Protection is paused. Ask your parent to turn it back on.',
                                      ),
                                      if (_protectionMode == 'friendly' &&
                                          _vpnOn) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          _vpnRequests.any(
                                            (request) =>
                                                request.status == 'pending',
                                          )
                                              ? 'Pause request pending parent approval.'
                                              : 'Friendly mode allows you to request a pause. A parent code is still required to turn protection off.',
                                        ),
                                      ],
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        width: double.infinity,
                                        child: FilledButton(
                                          onPressed: _applyingProtectionCode ||
                                                  !_family.isUsingSupabase
                                              ? null
                                              : _showProtectionCodeDialog,
                                          child: _applyingProtectionCode
                                              ? const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child: AppLoadingIndicator(
                                                      size: 20),
                                                )
                                              : Text(
                                                  'Enter parent approval',
                                                ),
                                        ),
                                      ),
                                      if (!_family.isUsingSupabase)
                                        const Padding(
                                          padding: EdgeInsets.only(top: 8),
                                          child: Text(
                                            'Ask your parent to finish setting up your account before using protection codes.',
                                            style: TextStyle(color: Colors.red),
                                          ),
                                        ),
                                      if (_protectionMode == 'friendly' &&
                                          _vpnOn)
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton.icon(
                                            onPressed: _vpnRequests.any(
                                              (request) =>
                                                  request.status == 'pending',
                                            )
                                                ? null
                                                : _requestProtectionPause,
                                            icon: const LiveIcon(Icons.send),
                                            label: const Text('Request pause'),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            if (_selectedSection == 2) ...[
                              Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: _usageOk
                                        ? Colors.blue.shade100
                                        : Colors.blue.shade100,
                                    child: LiveIcon(
                                      _usageOk
                                          ? Icons.check
                                          : Icons.warning_amber,
                                      color: _usageOk
                                          ? Colors.blue.shade800
                                          : Colors.blue.shade800,
                                    ),
                                  ),
                                  title: const Text(
                                    'App Usage Monitoring',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                    _usageOk
                                        ? 'Permission granted. Reporting app usage to parent.'
                                        : 'Required for accurate usage tracking and enforcing daily app limits. Android may require Allow restricted settings first.',
                                  ),
                                  trailing: _usageOk
                                      ? const LiveIcon(Icons.check_circle,
                                          color: Colors.blue)
                                      : FilledButton.tonal(
                                          onPressed: () => _showPermissionHelp(
                                            permissionName: 'Usage access',
                                            openPermissionSettings:
                                                _requestUsage,
                                          ),
                                          child: const Text('Set up'),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Accessibility App Blocker Card
                              Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: _a11yOk
                                        ? Colors.blue.shade100
                                        : Colors.blue.shade100,
                                    child: LiveIcon(
                                      _a11yOk
                                          ? Icons.check
                                          : Icons.warning_amber,
                                      color: _a11yOk
                                          ? Colors.blue.shade800
                                          : Colors.blue.shade800,
                                    ),
                                  ),
                                  title: const Text(
                                    'App Blocker Service',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                    _a11yOk
                                        ? 'Family app protections are active.'
                                        : 'Required to block apps and enforce their daily limits.',
                                  ),
                                  trailing: _a11yOk
                                      ? const LiveIcon(Icons.check_circle,
                                          color: Colors.blue)
                                      : FilledButton.tonal(
                                          onPressed: () => _showPermissionHelp(
                                            permissionName: 'Accessibility',
                                            openPermissionSettings:
                                                _requestA11y,
                                          ),
                                          child: const Text('Set up'),
                                        ),
                                ),
                              ),
                              if ((!_usageOk || !_a11yOk) &&
                                  (_timeLimits.isNotEmpty ||
                                      _blockedApps.isNotEmpty))
                                Card(
                                  color: Colors.blue.shade50,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      !_a11yOk
                                          ? 'App blocking and daily limits are not enforced until the App Blocker Accessibility service is enabled.'
                                          : 'Daily app limits are not enforced until Usage access is enabled.',
                                      style: TextStyle(
                                          color: Colors.blue.shade900),
                                    ),
                                  ),
                                ),
                            ],
                            if (_selectedSection == 2) ...[
                              if (_timeLimits.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Daily app limits',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        ..._timeLimits.map((limit) {
                                          final used = _dailyUsageSeconds[
                                                  limit.packageName] ??
                                              0;
                                          final allowed =
                                              limit.dailyLimitSeconds +
                                                  (_approvedExtraSeconds[
                                                          limit.packageName] ??
                                                      0);
                                          final pending =
                                              _extraTimeRequests.any(
                                            (request) =>
                                                request.packageName ==
                                                    limit.packageName &&
                                                request.status == 'pending',
                                          );
                                          return ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: Text(
                                              limit.appLabel.isEmpty
                                                  ? limit.packageName
                                                  : limit.appLabel,
                                            ),
                                            subtitle: Text(
                                              '${used ~/ 60} / ${allowed ~/ 60} min used today',
                                            ),
                                            trailing: TextButton(
                                              onPressed: pending
                                                  ? null
                                                  : () =>
                                                      _requestExtraTime(limit),
                                              child: Text(
                                                pending
                                                    ? 'Pending'
                                                    : 'Request time',
                                              ),
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              if (_streak != null &&
                                  (_streak!.bonusTimeMinutes > 0 ||
                                      _streak!.appUnlockCredits > 0)) ...[
                                const SizedBox(height: 12),
                                Card(
                                  child: ListTile(
                                    leading: const LiveIcon(Icons.redeem),
                                    title: const Text('Task streak rewards'),
                                    subtitle: Text(
                                      '${_streak!.bonusTimeMinutes} bonus minutes available for extra-time requests · ${_streak!.appUnlockCredits} temporary app unlock${_streak!.appUnlockCredits == 1 ? '' : 's'}',
                                    ),
                                    trailing: _streak!.appUnlockCredits > 0 &&
                                            _blockedApps.isNotEmpty
                                        ? PopupMenuButton<String>(
                                            tooltip:
                                                'Use a 15-minute app unlock',
                                            onSelected:
                                                _redeemTemporaryAppUnlock,
                                            itemBuilder: (context) =>
                                                _blockedApps
                                                    .map(
                                                      (packageName) =>
                                                          PopupMenuItem<String>(
                                                        value: packageName,
                                                        child: const Text(
                                                          'Family-restricted app',
                                                        ),
                                                      ),
                                                    )
                                                    .toList(),
                                            child: const Padding(
                                              padding: EdgeInsets.all(8),
                                              child: LiveIcon(Icons.lock_open),
                                            ),
                                          )
                                        : null,
                                  ),
                                ),
                              ],
                            ],
                            if (_selectedSection == 1) ...[
                              _buildChildTasks(),
                            ],
                          ],
                        ),
                ),
    );
  }
}
