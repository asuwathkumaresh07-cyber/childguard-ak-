import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared/shared.dart';
import 'package:url_launcher/url_launcher.dart';

class LocationRadar extends StatefulWidget {
  const LocationRadar({
    super.key,
    required this.location,
    required this.history,
    required this.zones,
  });

  final ChildLocation? location;
  final List<ChildLocation> history;
  final List<FamilyZone> zones;

  @override
  State<LocationRadar> createState() => _LocationRadarState();
}

class _LocationRadarState extends State<LocationRadar>
    with SingleTickerProviderStateMixin {
  final _mapController = MapController();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void didUpdateWidget(covariant LocationRadar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final location = widget.location;
    if (location != null && location != oldWidget.location) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mapController.move(
            LatLng(location.latitude, location.longitude),
            _mapController.camera.zoom,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _openAttribution() async {
    final uri = Uri.https('www.openstreetmap.org', '/copyright');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.location;
    final current = location == null
        ? const LatLng(20, 0)
        : LatLng(location.latitude, location.longitude);
    final track = widget.history
        .where((sample) =>
            location != null &&
            sample.childId == location.childId &&
            sample.recordedAt
                .isBefore(location.recordedAt.add(const Duration(seconds: 1))))
        .toList()
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: 310,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: current,
                initialZoom: location == null ? 2.5 : 15,
                minZoom: 2,
                maxZoom: 19,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.familyguard.parent',
                  maxNativeZoom: 19,
                ),
                CircleLayer(
                  circles: [
                    for (final zone in widget.zones)
                      CircleMarker(
                        point: LatLng(zone.latitude, zone.longitude),
                        radius: zone.radiusMeters.toDouble(),
                        useRadiusInMeter: true,
                        color: _zoneColor(zone.zoneType).withValues(alpha: .15),
                        borderColor:
                            _zoneColor(zone.zoneType).withValues(alpha: .85),
                        borderStrokeWidth: 2,
                      ),
                    if (location?.accuracyMeters case final accuracy?)
                      CircleMarker(
                        point: current,
                        radius: accuracy.clamp(10, 500).toDouble(),
                        useRadiusInMeter: true,
                        color: const Color(0xFF267B74).withValues(alpha: .12),
                        borderColor:
                            const Color(0xFF267B74).withValues(alpha: .34),
                        borderStrokeWidth: 1,
                      ),
                  ],
                ),
                if (track.length > 1)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [
                          for (final sample in track)
                            LatLng(sample.latitude, sample.longitude),
                        ],
                        strokeWidth: 4,
                        color: const Color(0xFF267B74),
                        borderStrokeWidth: 1,
                        borderColor: Colors.white,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    for (final zone in widget.zones)
                      Marker(
                        point: LatLng(zone.latitude, zone.longitude),
                        width: 100,
                        height: 42,
                        alignment: Alignment.bottomCenter,
                        child: _ZoneMapLabel(
                          name: zone.name,
                          color: _zoneColor(zone.zoneType),
                        ),
                      ),
                    if (location != null)
                      Marker(
                        point: current,
                        width: 54,
                        height: 54,
                        child: AnimatedBuilder(
                          animation: _pulse,
                          builder: (context, _) {
                            final pulse = _pulse.value;
                            return Center(
                              child: Container(
                                width: 24 + pulse * 26,
                                height: 24 + pulse * 26,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF24756E)
                                      .withValues(alpha: .22 * (1 - pulse)),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.white.withValues(alpha: .95),
                                      blurRadius: 4,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF24756E),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.person_pin_circle,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution(
                      '© OpenStreetMap contributors',
                      onTap: _openAttribution,
                    ),
                  ],
                  alignment: AttributionAlignment.bottomLeft,
                ),
              ],
            ),
            Positioned(
              right: 12,
              top: 12,
              child: Column(
                children: [
                  _MapControl(
                    icon: Icons.add,
                    tooltip: 'Zoom in',
                    onPressed: () => _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom + 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _MapControl(
                    icon: Icons.remove,
                    tooltip: 'Zoom out',
                    onPressed: () => _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom - 1,
                    ),
                  ),
                  if (location != null) ...[
                    const SizedBox(height: 8),
                    _MapControl(
                      icon: Icons.my_location,
                      tooltip: 'Center on child',
                      onPressed: () => _mapController.move(current, 15),
                    ),
                  ],
                ],
              ),
            ),
            if (location == null)
              Positioned(
                left: 12,
                right: 64,
                top: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .93),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Text(
                      'Waiting for the child’s first location update',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _zoneColor(String type) => switch (type) {
        'home' => const Color(0xFF388E75),
        'school' => const Color(0xFF5278C8),
        'tuition' => const Color(0xFFB87934),
        _ => const Color(0xFF8B65B7),
      };
}

class _ZoneMapLabel extends StatelessWidget {
  const _ZoneMapLabel({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 100),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .95),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: color.withValues(alpha: .7)),
          boxShadow: const [
            BoxShadow(color: Color(0x22000000), blurRadius: 5),
          ],
        ),
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _MapControl extends StatelessWidget {
  const _MapControl({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .96),
      elevation: 2,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
      ),
    );
  }
}
