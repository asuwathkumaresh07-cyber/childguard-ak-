import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared/shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/location_radar.dart';
import '../widgets/user_error.dart';

class ChildPlansScreen extends StatefulWidget {
  const ChildPlansScreen({
    super.key,
    required this.familyId,
    required this.childId,
    required this.childName,
  });

  final String familyId;
  final String childId;
  final String childName;

  @override
  State<ChildPlansScreen> createState() => _ChildPlansScreenState();
}

class _ChildPlansScreenState extends State<ChildPlansScreen> {
  final _family = FamilyService();
  bool _loading = true;
  String? _error;
  String? _insightError;
  String? _locationError;
  ChildLocation? _location;
  List<ChildLocation> _locationHistory = [];
  List<FamilyZone> _zones = [];
  List<ZoneAppRule> _zoneRules = [];
  List<ChildMoodCheckin> _moods = [];
  List<ZoneEvent> _zoneEvents = [];
  List<AppUsageLog> _usage = [];
  ChildWeeklyInsight? _insight;
  ChildStreak? _streak;
  ChildAutonomySettings? _autonomy;
  Map<String, String> _categories = {};
  RealtimeChannel? _locationRealtimeSub;
  RealtimeChannel? _insightRealtimeSub;
  Timer? _locationPoll;
  bool _locationRefreshInProgress = false;

  @override
  void initState() {
    super.initState();
    _locationRealtimeSub = _family.subscribeToChildLocations(
      widget.childId,
      _onLocationUpdate,
    );
    _insightRealtimeSub = _family.subscribeToChildWeeklyInsights(
      widget.childId,
      (insight) {
        if (!mounted ||
            insight.familyId != widget.familyId ||
            insight.childId != widget.childId) {
          return;
        }
        setState(() => _insight = insight);
      },
    );
    _locationPoll = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_refreshLocation()),
    );
    _load();
  }

  @override
  void dispose() {
    _locationRealtimeSub?.unsubscribe();
    _insightRealtimeSub?.unsubscribe();
    _locationPoll?.cancel();
    super.dispose();
  }

  void _onLocationUpdate(ChildLocation location) {
    if (!mounted ||
        location.familyId != widget.familyId ||
        location.childId != widget.childId ||
        (_location != null &&
            !location.recordedAt.isAfter(_location!.recordedAt))) {
      return;
    }
    setState(() {
      _location = location;
      _locationHistory = [
        location,
        ..._locationHistory.where((item) => item.id != location.id),
      ].take(48).toList();
      _locationError = null;
    });
  }

  Future<void> _refreshLocation() async {
    if (!_family.isUsingSupabase || _locationRefreshInProgress) return;
    _locationRefreshInProgress = true;
    try {
      final location = await _family.fetchLatestChildLocation(widget.childId);
      if (!mounted) return;
      setState(() {
        if (location != null &&
            location.familyId == widget.familyId &&
            location.childId == widget.childId &&
            (_location == null ||
                location.recordedAt.isAfter(_location!.recordedAt))) {
          _location = location;
        }
        _locationError = null;
      });
      try {
        final history = await _family.fetchChildLocationHistory(widget.childId);
        if (!mounted) return;
        setState(() {
          _locationHistory = history
              .where((sample) =>
                  sample.familyId == widget.familyId &&
                  sample.childId == widget.childId)
              .toList();
          _locationError = null;
        });
      } catch (error) {
        reportAppError('refresh child location history', error);
        if (mounted) setState(() => _locationError = userFacingError);
      }
    } catch (error) {
      reportAppError('refresh child location', error);
      if (mounted) setState(() => _locationError = userFacingError);
    } finally {
      _locationRefreshInProgress = false;
    }
  }

  Future<void> _openLocationInMaps() async {
    final location = _location;
    if (location == null) return;
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '${location.latitude},${location.longitude}',
    });
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _showMessage(userFacingError);
      }
    } catch (error) {
      _showError('open map', error);
    }
  }

  Future<void> _load() async {
    if (!_family.isUsingSupabase) {
      reportAppError(
        'load child plans',
        StateError('The family service is not connected.'),
      );
      setState(() {
        _loading = false;
        _error = userFacingError;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    unawaited(_refreshLocation());
    try {
      final values = await Future.wait([
        _family.fetchFamilyZones(widget.familyId),
        _family.fetchZoneAppRules(widget.familyId),
        _family.fetchChildMoodCheckins(
          familyId: widget.familyId,
          childId: widget.childId,
        ),
        _family.fetchAppUsageLogs(
          familyId: widget.familyId,
          childId: widget.childId,
          limit: 1000,
        ),
        _family.fetchLatestChildWeeklyInsight(widget.childId),
        _family.fetchChildStreak(widget.childId),
        _family.fetchChildAppCategories(widget.familyId),
        _family.fetchZoneEvents(
          familyId: widget.familyId,
          childId: widget.childId,
        ),
        _family.fetchChildAutonomySettings(
          familyId: widget.familyId,
          childId: widget.childId,
        ),
      ]);
      var insight = values[4] as ChildWeeklyInsight?;
      String? insightError;
      final now = DateTime.now();
      final currentWeekStart = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - DateTime.monday));
      if (insight == null || insight.weekStart.isBefore(currentWeekStart)) {
        try {
          insight = await _family.generateChildWeeklyInsight(
            familyId: widget.familyId,
            childId: widget.childId,
          );
        } catch (error) {
          reportAppError('refresh weekly insight', error);
          insightError = userFacingError;
        }
      }
      if (!mounted) return;
      setState(() {
        _zones = values[0] as List<FamilyZone>;
        _zoneRules = values[1] as List<ZoneAppRule>;
        _moods = values[2] as List<ChildMoodCheckin>;
        _usage = values[3] as List<AppUsageLog>;
        _insight = insight;
        _insightError = insightError;
        _streak = values[5] as ChildStreak?;
        _categories = values[6] as Map<String, String>;
        _zoneEvents = values[7] as List<ZoneEvent>;
        _autonomy = values[8] as ChildAutonomySettings;
        _loading = false;
      });
    } catch (error) {
      reportAppError('load child plans', error);
      if (mounted) {
        setState(() {
          _loading = false;
          _error = userFacingError;
        });
      }
    }
  }

  Future<void> _createZone() async {
    final location = _location;
    final name = TextEditingController();
    final latitude = TextEditingController(
      text: location?.latitude.toStringAsFixed(6) ?? '',
    );
    final longitude = TextEditingController(
      text: location?.longitude.toStringAsFixed(6) ?? '',
    );
    var type = 'school';
    var radius = 550;
    String? validationMessage;
    try {
      final values = await showDialog<(String, String, int, double, double)>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Add a known place'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Place name',
                      hintText: 'e.g. Green Valley School',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Place type'),
                    items: const [
                      DropdownMenuItem(value: 'home', child: Text('Home')),
                      DropdownMenuItem(
                        value: 'school',
                        child: Text('School'),
                      ),
                      DropdownMenuItem(
                        value: 'tuition',
                        child: Text('Tuition center'),
                      ),
                      DropdownMenuItem(
                        value: 'custom',
                        child: Text('Other place'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => type = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: radius,
                    decoration:
                        const InputDecoration(labelText: 'Safe-zone size'),
                    items: const [500, 550, 600]
                        .map(
                          (meters) => DropdownMenuItem(
                            value: meters,
                            child: Text('$meters meters'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setDialogState(() => radius = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Location coordinates',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: latitude,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Latitude',
                            hintText: '12.9716',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: longitude,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Longitude',
                            hintText: '77.5946',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Coordinates are prefilled from the latest child location. You can replace them with a known place’s coordinates.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (location != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setDialogState(() {
                          latitude.text = location.latitude.toStringAsFixed(6);
                          longitude.text =
                              location.longitude.toStringAsFixed(6);
                        }),
                        icon: const Icon(Icons.my_location, size: 18),
                        label: const Text("Use child's latest location"),
                      ),
                    ),
                  if (validationMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      validationMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final lat = double.tryParse(latitude.text.trim());
                  final lon = double.tryParse(longitude.text.trim());
                  if (name.text.trim().isEmpty) {
                    setDialogState(
                      () => validationMessage = 'Enter a place name.',
                    );
                  } else if (lat == null ||
                      lon == null ||
                      lat < -90 ||
                      lat > 90 ||
                      lon < -180 ||
                      lon > 180) {
                    setDialogState(
                      () => validationMessage =
                          'Enter valid latitude and longitude values.',
                    );
                  } else {
                    Navigator.pop(
                      context,
                      (
                        name.text.trim(),
                        type,
                        radius,
                        lat,
                        lon,
                      ),
                    );
                  }
                },
                child: const Text('Save place'),
              ),
            ],
          ),
        ),
      );
      if (values == null) return;
      await _family.saveFamilyZone(
        familyId: widget.familyId,
        name: values.$1,
        zoneType: values.$2,
        radiusMeters: values.$3,
        latitude: values.$4,
        longitude: values.$5,
      );
      await _load();
    } catch (error) {
      _showError('save zone', error);
    } finally {
      name.dispose();
      latitude.dispose();
      longitude.dispose();
    }
  }

  Future<void> _addZoneRule(FamilyZone zone) async {
    final package = TextEditingController();
    final label = TextEditingController();
    try {
      final values = await showDialog<(String, String)>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Restrict apps in ${zone.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: label,
                decoration: const InputDecoration(labelText: 'App name'),
              ),
              TextField(
                controller: package,
                decoration: const InputDecoration(
                  labelText: 'Android package name',
                  hintText: 'com.example.app',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (package.text.trim().isEmpty) return;
                Navigator.pop(
                  context,
                  (package.text.trim(), label.text.trim()),
                );
              },
              child: const Text('Add restriction'),
            ),
          ],
        ),
      );
      if (values == null) return;
      await _family.saveZoneAppRule(
        familyId: widget.familyId,
        zoneId: zone.id,
        packageName: values.$1,
        appLabel: values.$2,
      );
      await _load();
    } catch (error) {
      _showError('add zone restriction', error);
    } finally {
      package.dispose();
      label.dispose();
    }
  }

  Future<void> _generateInsight() async {
    try {
      final insight = await _family.generateChildWeeklyInsight(
        familyId: widget.familyId,
        childId: widget.childId,
      );
      if (mounted) {
        setState(() {
          _insight = insight;
          _insightError = null;
        });
      }
    } catch (error) {
      _showError('generate weekly insight', error);
    }
  }

  Future<void> _configureAutonomy() async {
    final current = _autonomy ??
        ChildAutonomySettings(
          childId: widget.childId,
          familyId: widget.familyId,
          enabled: false,
          minTrustScore: 80,
          dailyExtraMinutesCap: 15,
        );
    var enabled = current.enabled;
    var minimumScore = current.minTrustScore.toDouble();
    final cap = TextEditingController(
      text: current.dailyExtraMinutesCap.toString(),
    );
    try {
      final values = await showDialog<(bool, int, int)>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Trust-based autonomy'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable automatic extra time'),
                    subtitle: const Text(
                      'VPN changes and core protection still require a parent code.',
                    ),
                    value: enabled,
                    onChanged: (value) => setDialogState(() => enabled = value),
                  ),
                  Text(
                    'Minimum trust score: ${minimumScore.round()}',
                  ),
                  Slider(
                    value: minimumScore,
                    min: 50,
                    max: 100,
                    divisions: 50,
                    label: minimumScore.round().toString(),
                    onChanged: (value) =>
                        setDialogState(() => minimumScore = value),
                  ),
                  TextField(
                    controller: cap,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Daily automatic extra-time cap (minutes)',
                      helperText: 'Shared across apps; 1 to 120 minutes.',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final capMinutes = int.tryParse(cap.text) ?? 0;
                  if (capMinutes < 1 || capMinutes > 120) return;
                  Navigator.pop(
                    context,
                    (enabled, minimumScore.round(), capMinutes),
                  );
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
      if (values == null) return;
      await _family.saveChildAutonomySettings(
        familyId: widget.familyId,
        childId: widget.childId,
        enabled: values.$1,
        minTrustScore: values.$2,
        dailyExtraMinutesCap: values.$3,
      );
      if (mounted) {
        setState(() {
          _autonomy = ChildAutonomySettings(
            childId: widget.childId,
            familyId: widget.familyId,
            enabled: values.$1,
            minTrustScore: values.$2,
            dailyExtraMinutesCap: values.$3,
          );
        });
      }
    } catch (error) {
      _showError('save autonomy settings', error);
    } finally {
      cap.dispose();
    }
  }

  Future<void> _setCategory(String packageName, String category) async {
    try {
      await _family.saveChildAppCategory(
        familyId: widget.familyId,
        packageName: packageName,
        category: category,
      );
      if (mounted) setState(() => _categories[packageName] = category);
    } catch (error) {
      _showError('categorize app', error);
    }
  }

  Future<void> _removeZone(FamilyZone zone) async {
    try {
      await _family.removeFamilyZone(widget.familyId, zone.id);
      await _load();
    } catch (error) {
      _showError('remove zone', error);
    }
  }

  Future<void> _removeRule(ZoneAppRule rule) async {
    try {
      await _family.removeZoneAppRule(rule.id);
      await _load();
    } catch (error) {
      _showError('remove zone restriction', error);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showError(String action, Object error) {
    reportAppError(action, error);
    _showMessage(userFacingError);
  }

  FamilyZone? get _activeZone {
    final current = _location;
    if (current == null) return null;
    for (final zone in _zones) {
      if (_distanceMeters(
            current.latitude,
            current.longitude,
            zone.latitude,
            zone.longitude,
          ) <=
          zone.radiusMeters) {
        return zone;
      }
    }
    return null;
  }

  double _distanceMeters(
    double latitude1,
    double longitude1,
    double latitude2,
    double longitude2,
  ) {
    const earthRadius = 6371000.0;
    final latDelta = (latitude2 - latitude1) * math.pi / 180;
    final lonDelta = (longitude2 - longitude1) * math.pi / 180;
    final a = math.pow(math.sin(latDelta / 2), 2) +
        math.cos(latitude1 * math.pi / 180) *
            math.cos(latitude2 * math.pi / 180) *
            math.pow(math.sin(lonDelta / 2), 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  String _locationFreshness(ChildLocation? location) {
    if (location == null) return 'Waiting';
    final age = DateTime.now().difference(location.recordedAt.toLocal());
    if (age.inMinutes < 3) return 'Live';
    if (age.inMinutes < 20) return 'Recent';
    return 'Stale';
  }

  Widget _sectionTitle(String title, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final apps = {
      for (final log in _usage)
        log.packageName: log.appLabel.isEmpty ? log.packageName : log.appLabel,
    };
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(_error!),
                trailing: IconButton(
                  tooltip: 'Retry',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ),
          _sectionTitle(
            'Location & zones',
            trailing: IconButton(
              tooltip: 'Refresh',
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
          ),
          GlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.radar, color: Color(0xFF347A75)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _location == null
                            ? 'Waiting for location'
                            : '${widget.childName} · ${_locationFreshness(_location)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (_location != null)
                      Text(
                        DateFormat('h:mm a')
                            .format(_location!.recordedAt.toLocal()),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                LocationRadar(
                  location: _location,
                  history: _locationHistory,
                  zones: _zones,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      _activeZone == null
                          ? Icons.near_me_outlined
                          : Icons.location_on,
                      size: 18,
                      color: _activeZone == null
                          ? const Color(0xFF628187)
                          : const Color(0xFF2D806D),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _location == null
                            ? 'Waiting for the first update. Turn on “Share my location” in the Child app.'
                            : _locationFreshness(_location) == 'Stale'
                                ? 'Last seen ${_activeZone == null ? 'outside saved places' : 'at ${_activeZone!.name}'} · update is stale'
                                : _activeZone == null
                                    ? 'Unknown place · outside saved places'
                                    : 'At ${_activeZone!.name}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (_location?.accuracyMeters != null)
                      Text(
                        '±${_location!.accuracyMeters!.round()} m',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
                if (_locationError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    userFacingError,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _location == null ? null : _openLocationInMaps,
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('View location'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _createZone,
                      icon: const Icon(Icons.add_location_alt),
                      label: const Text('Add known place'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_zones.isEmpty)
            const Text(
              'No saved places yet. Add Home, School, or Tuition to see whether your child is at a known place.',
            )
          else
            ..._zones.map((zone) {
              final rules = _zoneRules.where((r) => r.zoneId == zone.id);
              return Card(
                child: ExpansionTile(
                  title: Text(zone.name),
                  subtitle: Text(
                    '${zone.zoneType} · ${zone.radiusMeters} m radius',
                  ),
                  trailing: IconButton(
                    tooltip: 'Delete zone',
                    onPressed: () => _removeZone(zone),
                    icon: const Icon(Icons.delete_outline),
                  ),
                  children: [
                    ...rules.map(
                      (rule) => ListTile(
                        dense: true,
                        title: Text(
                          rule.appLabel.isEmpty
                              ? rule.packageName
                              : rule.appLabel,
                        ),
                        subtitle: Text(rule.packageName),
                        trailing: IconButton(
                          onPressed: () => _removeRule(rule),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _addZoneRule(zone),
                      icon: const Icon(Icons.add),
                      label: const Text('Restrict an app in this zone'),
                    ),
                  ],
                ),
              );
            }),
          if (_zoneEvents.isNotEmpty) ...[
            _sectionTitle('Recent zone events'),
            ..._zoneEvents.take(10).map((event) {
              final zone = _zones.where((item) => item.id == event.zoneId);
              final zoneName = zone.isEmpty ? 'Zone' : zone.first.name;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  event.eventType == 'off_task_app'
                      ? Icons.warning_amber
                      : Icons.place,
                ),
                title: Text(
                  event.eventType == 'off_task_app'
                      ? '${event.packageName ?? 'App'} in $zoneName'
                      : '${event.eventType} $zoneName',
                ),
                subtitle: Text(
                  DateFormat('MMM d, h:mm a')
                      .format(event.occurredAt.toLocal()),
                ),
                trailing: event.eventType == 'off_task_app' && zone.isNotEmpty
                    ? IconButton(
                        tooltip: 'Restrict this app in this zone',
                        onPressed: () => _addZoneRule(zone.first),
                        icon: const Icon(Icons.block),
                      )
                    : null,
              );
            }),
          ],
          _sectionTitle(
            'Weekly trust & insights',
            trailing: FilledButton.tonal(
              onPressed: _generateInsight,
              child: const Text('Generate'),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.insights),
              title: Text(
                _insight == null
                    ? 'No weekly summary yet'
                    : 'Trust score: ${_insight!.trustScore}/100',
              ),
              subtitle: Text(
                _insight?.summary ??
                    'Generate a summary from recorded app use, completed tasks, and protection events.',
              ),
            ),
          ),
          if (_insightError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                _insightError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_insight?.moodAlert == true)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.health_and_safety_outlined),
                title: const Text('Consider a supportive check-in'),
                subtitle: Text(
                  _insight!.moodAlertReason ??
                      'Recent mood check-ins may need a supportive conversation.',
                ),
              ),
            ),
          if (_streak != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.local_fire_department),
                title: Text(
                  '${_streak!.currentStreak} approved-task streak · ${_streak!.totalPoints} points',
                ),
                subtitle: Text(
                  'Best: ${_streak!.bestStreak} tasks · '
                  '${_streak!.bonusTimeMinutes} bonus minutes · '
                  '${_streak!.appUnlockCredits} app unlocks available',
                ),
              ),
            ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.tune),
              title: Text(
                _autonomy?.enabled == true
                    ? 'Automatic extra time is enabled'
                    : 'Automatic extra time is off',
              ),
              subtitle: Text(
                _autonomy?.enabled == true
                    ? 'At score ${_autonomy!.minTrustScore}, up to ${_autonomy!.dailyExtraMinutesCap} minutes per day across apps.'
                    : 'Set a trust threshold and daily cap. Parent-issued VPN codes remain required.',
              ),
              trailing: IconButton(
                tooltip: 'Configure trust-based autonomy',
                onPressed: _configureAutonomy,
                icon: const Icon(Icons.settings),
              ),
            ),
          ),
          _sectionTitle('App activity categories'),
          if (apps.isEmpty)
            const Text('App usage will appear after the child device syncs.')
          else
            ...apps.entries.map(
              (entry) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.value),
                subtitle: Text(entry.key),
                trailing: DropdownButton<String>(
                  value: _categories[entry.key] ?? 'unproductive',
                  items: const [
                    DropdownMenuItem(
                      value: 'educational',
                      child: Text('Educational'),
                    ),
                    DropdownMenuItem(
                      value: 'creative',
                      child: Text('Creative'),
                    ),
                    DropdownMenuItem(
                      value: 'social',
                      child: Text('Social'),
                    ),
                    DropdownMenuItem(
                      value: 'entertainment',
                      child: Text('Entertainment'),
                    ),
                    DropdownMenuItem(
                      value: 'unproductive',
                      child: Text('Unproductive'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) _setCategory(entry.key, value);
                  },
                ),
              ),
            ),
          _sectionTitle('Recent mood check-ins'),
          if (_moods.isEmpty)
            const Text('No mood check-ins have been submitted.')
          else
            ..._moods.take(10).map(
                  (mood) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.mood),
                    title: Text(mood.mood),
                    subtitle: Text(
                      '${DateFormat('MMM d, h:mm a').format(mood.createdAt.toLocal())}'
                      '${mood.note.isEmpty ? '' : ' · ${mood.note}'}',
                    ),
                  ),
                ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
