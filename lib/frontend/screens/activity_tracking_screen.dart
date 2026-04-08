import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/health_service.dart';

enum ActivityMode { walk, run, bike }
enum ActivityMapMode { normal, satellite }

class ActivityTrackingScreen extends StatefulWidget {
  const ActivityTrackingScreen({
    super.key,
    required this.todaySteps,
  });

  final int todaySteps;

  @override
  State<ActivityTrackingScreen> createState() => _ActivityTrackingScreenState();
}

class _ActivityTrackingScreenState extends State<ActivityTrackingScreen> {
  static const LatLng _defaultCenter = LatLng(10.7769, 106.7009);
  static const Duration _autoSaveInterval = Duration(seconds: 10);
  static const double _bikeSoftWarningKmh = 40;
  static const double _bikeHardWarningKmh = 48;
  static const int _highSpeedStreakToShow = 2;

  final HealthService _healthService = HealthService();
  final MapController _mapController = MapController();

  ActivityMode _activityMode = ActivityMode.walk;
  ActivityMapMode _mapMode = ActivityMapMode.normal;
  bool _isTracking = false;
  int _todaySteps = 0;
  double _sessionDistanceMeters = 0;
  LatLng _currentPoint = _defaultCenter;
  LatLng? _previousPoint;
  final List<LatLng> _path = <LatLng>[];
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<int>? _stepsSub;
  DateTime? _previousFixTime;
  DateTime? _sessionStartedAt;
  int _sessionStartSteps = 0;
  double _speedAccumulator = 0;
  int _speedSamples = 0;
  List<Map<String, dynamic>> _recentSessions = const [];
  final Map<ActivityMode, double> _modeDistanceMeters = {
    ActivityMode.walk: 0,
    ActivityMode.run: 0,
    ActivityMode.bike: 0,
  };
  Timer? _autoSaveTimer;
  String? _activeSessionId;
  bool _hasMapFix = false;
  int _bikeSpeedWarningLevel = 0;
  int _highSpeedStreak = 0;
  double _latestSpeedKmh = 0;
  String _todayPathKey = '';
  double _weeklyTotalMetersSaved = 0;
  final Map<ActivityMode, double> _weeklyModeMetersSaved = {
    ActivityMode.walk: 0,
    ActivityMode.run: 0,
    ActivityMode.bike: 0,
  };
  double _todayMetersSaved = 0;
  int _todayDurationSecSaved = 0;

  @override
  void initState() {
    super.initState();
    _todaySteps = widget.todaySteps;
    _path.add(_defaultCenter);
    _stepsSub = _healthService.stepsStream.listen((steps) {
      if (!mounted) return;
      setState(() => _todaySteps = steps);
    });
    _loadActivitySummaries();
    _loadRecentSessions();
    unawaited(_loadTodayPath());
    unawaited(_initCurrentLocation());
  }

  @override
  void dispose() {
    if (_isTracking) {
      _positionSub?.cancel();
      unawaited(_saveFinishedSession());
    }
    _autoSaveTimer?.cancel();
    _positionSub?.cancel();
    _stepsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadRecentSessions() async {
    final sessions = await _healthService.getActivitySessions(limit: 20);
    if (!mounted) return;
    setState(() => _recentSessions = sessions);
  }

  Future<void> _initCurrentLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      const currentLocationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
      );
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: currentLocationSettings,
      );
      final point = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _hasMapFix = true;
        _currentPoint = point;
        _previousPoint = point;
        if (_path.isEmpty) {
          _path.add(point);
        }
      });
      _moveMapToCurrent();
    } catch (_) {
      // Keep default center if current location cannot be fetched.
    }
  }

  void _moveMapToCurrent() {
    try {
      _mapController.move(_currentPoint, 16);
    } catch (_) {
      // Ignore until map has attached the controller.
    }
  }

  String _bikeSpeedWarningText() {
    if (_bikeSpeedWarningLevel >= 2) {
      return 'Toc do gan 50 km/h (${_latestSpeedKmh.toStringAsFixed(1)}), canh bao sai mode Bike';
    }
    return 'Toc do tren 40 km/h (${_latestSpeedKmh.toStringAsFixed(1)}), kiem tra co phai xe dap';
  }

  String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadTodayPath() async {
    final prefs = await SharedPreferences.getInstance();
    _todayPathKey = _dateKey(DateTime.now());
    final rows = prefs.getStringList('activity_path_$_todayPathKey') ?? [];
    if (rows.isEmpty || !mounted) return;

    final points = <LatLng>[];
    for (final row in rows) {
      final parts = row.split(',');
      if (parts.length != 2) continue;
      final lat = double.tryParse(parts[0]);
      final lng = double.tryParse(parts[1]);
      if (lat != null && lng != null) {
        points.add(LatLng(lat, lng));
      }
    }
    if (points.isEmpty || !mounted) return;

    setState(() {
      _path
        ..clear()
        ..addAll(points);
      _currentPoint = points.last;
      _previousPoint = points.last;
      _hasMapFix = true;
    });
    _moveMapToCurrent();
  }

  Future<void> _saveTodayPath() async {
    final prefs = await SharedPreferences.getInstance();
    if (_todayPathKey.isEmpty) {
      _todayPathKey = _dateKey(DateTime.now());
    }
    final rows = _path
        .map((p) => '${p.latitude},${p.longitude}')
        .toList(growable: false);
    await prefs.setStringList('activity_path_$_todayPathKey', rows);
  }

  Future<void> _loadActivitySummaries() async {
    final sessions = await _healthService.getActivitySessions(limit: 300);
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));

    double weeklyTotal = 0;
    double weeklyWalk = 0;
    double weeklyRun = 0;
    double weeklyBike = 0;
    double todayTotal = 0;
    int todayDuration = 0;

    for (final item in sessions) {
      final endRaw = (item['endedAt'] ?? '').toString();
      final endedAt = DateTime.tryParse(endRaw);
      if (endedAt == null) continue;

      final day = DateTime(endedAt.year, endedAt.month, endedAt.day);
      final inWeek = !day.isBefore(weekStart);
      final inToday = day == todayStart;
      final distanceMeters = (item['distanceMeters'] as num?)?.toDouble() ?? 0;
      final durationSec = (item['durationSec'] as num?)?.toInt() ?? 0;

      if (inToday) {
        todayTotal += distanceMeters;
        todayDuration += durationSec;
      }

      if (!inWeek) continue;
      weeklyTotal += distanceMeters;

      final segments = item['segments'];
      if (segments is List && segments.isNotEmpty) {
        for (final raw in segments) {
          if (raw is! Map) continue;
          final mode = (raw['mode'] ?? '').toString().toLowerCase();
          final meters = (raw['distanceMeters'] as num?)?.toDouble() ?? 0;
          if (mode == 'walk') weeklyWalk += meters;
          if (mode == 'run' || mode == 'running') weeklyRun += meters;
          if (mode == 'bike') weeklyBike += meters;
        }
      } else {
        final mode = (item['mode'] ?? '').toString().toLowerCase();
        if (mode == 'walk') weeklyWalk += distanceMeters;
        if (mode == 'run' || mode == 'running') weeklyRun += distanceMeters;
        if (mode == 'bike') weeklyBike += distanceMeters;
      }
    }

    if (!mounted) return;
    setState(() {
      _weeklyTotalMetersSaved = weeklyTotal;
      _weeklyModeMetersSaved[ActivityMode.walk] = weeklyWalk;
      _weeklyModeMetersSaved[ActivityMode.run] = weeklyRun;
      _weeklyModeMetersSaved[ActivityMode.bike] = weeklyBike;
      _todayMetersSaved = todayTotal;
      _todayDurationSecSaved = todayDuration;
    });
  }

  double _goalKm(ActivityMode mode) {
    switch (mode) {
      case ActivityMode.walk:
        return 5;
      case ActivityMode.run:
        return 8;
      case ActivityMode.bike:
        return 15;
    }
  }

  String _modeLabel(ActivityMode mode) {
    switch (mode) {
      case ActivityMode.walk:
        return 'Walk';
      case ActivityMode.run:
        return 'Running';
      case ActivityMode.bike:
        return 'Bike';
    }
  }

  IconData _modeIcon(ActivityMode mode) {
    switch (mode) {
      case ActivityMode.walk:
        return Icons.directions_walk;
      case ActivityMode.run:
        return Icons.directions_run;
      case ActivityMode.bike:
        return Icons.directions_bike;
    }
  }

  Color _modeColor(ActivityMode mode) {
    switch (mode) {
      case ActivityMode.walk:
        return const Color(0xFFCFAE85);
      case ActivityMode.run:
        return const Color(0xFFEF8C3B);
      case ActivityMode.bike:
        return const Color(0xFF6EA3D8);
    }
  }

  double get _todayDistanceKm {
    var meters = _todayMetersSaved + (_isTracking ? _sessionDistanceMeters : 0);
    if (meters <= 0 && _todaySteps > 0) {
      meters = _healthService.getDistanceM(_todaySteps);
    }
    return meters / 1000;
  }

  double get _weeklyDistanceKm =>
      (_weeklyTotalMetersSaved + (_isTracking ? _sessionDistanceMeters : 0)) / 1000;

  int get _todayDurationSec {
    final activeSec = _isTracking && _sessionStartedAt != null
        ? DateTime.now().difference(_sessionStartedAt!).inSeconds
        : 0;
    return _todayDurationSecSaved + activeSec;
  }

  int get _currentSessionDurationSec {
    if (!_isTracking || _sessionStartedAt == null) return 0;
    return DateTime.now().difference(_sessionStartedAt!).inSeconds;
  }

  @override
  Widget build(BuildContext context) {
    final modeColor = _modeColor(_activityMode);
    final progress = (_todayDistanceKm / _goalKm(_activityMode)).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2F3F5),
        foregroundColor: Colors.black87,
        elevation: 0,
        title: const Text('Sports', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        child: Column(
          children: [
            _buildActivityTabs(modeColor),
            const SizedBox(height: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _currentPoint,
                        initialZoom: 13,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: _mapMode == ActivityMapMode.normal
                              ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
                              : 'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                          userAgentPackageName: 'com.betterme.betterme',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _currentPoint,
                              width: 42,
                              height: 42,
                              child: Icon(Icons.my_location, color: modeColor, size: 30),
                            ),
                          ],
                        ),
                        if (_path.length > 1)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: _path,
                                strokeWidth: 4,
                                color: modeColor.withValues(alpha: 0.8),
                              ),
                            ],
                          ),
                      ],
                    ),
                    Positioned(
                      right: 12,
                      top: 12,
                      child: _buildMapTypeSwitch(),
                    ),
                    if (_hasMapFix)
                      Positioned(
                        left: 12,
                        top: 12,
                        child: _buildRecenterButton(),
                      ),
                    if (!_hasMapFix)
                      const Positioned(
                        left: 12,
                        top: 12,
                        child: _MapHintChip(text: 'Dang bat vi tri GPS...'),
                      ),
                    if (_bikeSpeedWarningLevel > 0)
                      Positioned(
                        top: 58,
                        child: _MapHintChip(text: _bikeSpeedWarningText()),
                      ),
                    _buildCenterRing(modeColor, progress),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 14,
                      child: _buildBottomControls(modeColor),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityTabs(Color modeColor) {
    return Row(
      children: [
        Expanded(child: _tabButton(ActivityMode.walk, modeColor)),
        const SizedBox(width: 8),
        Expanded(child: _tabButton(ActivityMode.run, modeColor)),
        const SizedBox(width: 8),
        Expanded(child: _tabButton(ActivityMode.bike, modeColor)),
      ],
    );
  }

  Widget _tabButton(ActivityMode mode, Color modeColor) {
    final selected = _activityMode == mode;
    return GestureDetector(
      onTap: () => _onModeSelected(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? modeColor : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? modeColor : const Color(0xFFE1E1E4)),
        ),
        child: Center(
          child: Text(
            _modeLabel(mode),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMapTypeSwitch() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _mapChip('Gốc', ActivityMapMode.normal),
          _mapChip('Vệ tinh', ActivityMapMode.satellite),
        ],
      ),
    );
  }

  Widget _mapChip(String label, ActivityMapMode mode) {
    final selected = _mapMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _mapMode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Colors.black87 : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildRecenterButton() {
    return GestureDetector(
      onTap: _moveMapToCurrent,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(Icons.my_location, color: Colors.black87, size: 20),
      ),
    );
  }

  Widget _buildCenterRing(Color modeColor, double progress) {
    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.95),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 190,
            height: 190,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 9,
              backgroundColor: const Color(0xFFE5E5E9),
              valueColor: AlwaysStoppedAnimation<Color>(modeColor),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_modeIcon(_activityMode), color: modeColor, size: 24),
              const SizedBox(height: 8),
              Text(
                _todayDistanceKm.toStringAsFixed(2),
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              const Text(
                'KM',
                style: TextStyle(
                  letterSpacing: 1,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Tuần này: ${_weeklyDistanceKm.toStringAsFixed(1)} km',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                'Run ${((_weeklyModeMetersSaved[ActivityMode.run] ?? 0) / 1000).toStringAsFixed(1)} • Walk ${((_weeklyModeMetersSaved[ActivityMode.walk] ?? 0) / 1000).toStringAsFixed(1)} • Bike ${((_weeklyModeMetersSaved[ActivityMode.bike] ?? 0) / 1000).toStringAsFixed(1)} km',
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.black45,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Hom nay: ${_todayDistanceKm.toStringAsFixed(2)} km • ${_formatDuration(_todayDurationSec)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_isTracking) ...[
                const SizedBox(height: 4),
                Text(
                  'Phien hien tai: ${(_sessionDistanceMeters / 1000).toStringAsFixed(2)} km • ${_formatDuration(_currentSessionDurationSec)}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.black45,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Run ${( (_modeDistanceMeters[ActivityMode.run] ?? 0) / 1000).toStringAsFixed(2)} • Walk ${( (_modeDistanceMeters[ActivityMode.walk] ?? 0) / 1000).toStringAsFixed(2)} • Bike ${( (_modeDistanceMeters[ActivityMode.bike] ?? 0) / 1000).toStringAsFixed(2)} km',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.black45,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(Color modeColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _smallAction(
          icon: Icons.settings,
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tùy chọn theo dõi sẽ có ở bản cập nhật tới.')),
          ),
        ),
        GestureDetector(
          onTap: _toggleTracking,
          child: Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: modeColor,
              boxShadow: [
                BoxShadow(
                  color: modeColor.withValues(alpha: 0.45),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(
              _isTracking ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 44,
            ),
          ),
        ),
        _smallAction(
          icon: Icons.bar_chart,
          onTap: _showSessionHistorySheet,
        ),
      ],
    );
  }

  Widget _smallAction({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.black54),
      ),
    );
  }

  Future<void> _toggleTracking() async {
    if (_isTracking) {
      await _positionSub?.cancel();
      _positionSub = null;
      _autoSaveTimer?.cancel();
      await _saveFinishedSession();
      if (!mounted) return;
      setState(() {
        _isTracking = false;
        _bikeSpeedWarningLevel = 0;
        _highSpeedStreak = 0;
      });
      return;
    }

    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng bật GPS để bắt đầu theo dõi hoạt động.')),
      );
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ứng dụng cần quyền vị trí để đếm bước theo di chuyển thực tế.')),
      );
      return;
    }

    await _positionSub?.cancel();
    await _initCurrentLocation();
    _previousPoint = null;
    _previousFixTime = null;
    _sessionDistanceMeters = 0;
    _sessionStartedAt = DateTime.now();
    _activeSessionId = _sessionStartedAt!.millisecondsSinceEpoch.toString();
    _sessionStartSteps = _todaySteps;
    _speedAccumulator = 0;
    _speedSamples = 0;
    _highSpeedStreak = 0;
    _latestSpeedKmh = 0;
    _bikeSpeedWarningLevel = 0;
    _modeDistanceMeters.updateAll((key, value) => 0);
    if (_path.isEmpty) {
      _path.add(_currentPoint);
    }

    if (!mounted) return;
    setState(() => _isTracking = true);
    _startAutoSave();

    const settings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 3,
    );

    _positionSub = Geolocator.getPositionStream(locationSettings: settings).listen((position) async {
      final nextPoint = LatLng(position.latitude, position.longitude);
      final now = position.timestamp;

      if (_previousPoint != null) {
        final delta = Geolocator.distanceBetween(
          _previousPoint!.latitude,
          _previousPoint!.longitude,
          nextPoint.latitude,
          nextPoint.longitude,
        );

        final timeDeltaSec = _previousFixTime == null
            ? 0.0
            : now.difference(_previousFixTime!).inMilliseconds / 1000.0;
        final streamSpeed = position.speed > 0 ? position.speed : 0.0;
        final distanceSpeed = (timeDeltaSec > 0 && delta > 0)
            ? (delta / timeDeltaSec)
            : 0.0;
        final effectiveSpeed = streamSpeed > 0.2 ? streamSpeed : distanceSpeed;
        final speedKmh = effectiveSpeed * 3.6;

        var nextWarningLevel = 0;
        if (_activityMode == ActivityMode.bike && speedKmh >= _bikeHardWarningKmh) {
          nextWarningLevel = 2;
        } else if (_activityMode == ActivityMode.bike && speedKmh >= _bikeSoftWarningKmh) {
          nextWarningLevel = 1;
        }

        if (nextWarningLevel > 0) {
          _highSpeedStreak += 1;
        } else {
          _highSpeedStreak = 0;
        }

        _latestSpeedKmh = speedKmh;
        _bikeSpeedWarningLevel = _highSpeedStreak >= _highSpeedStreakToShow
            ? nextWarningLevel
            : 0;

        // Lọc rung GPS: chỉ cộng khi thay đổi vị trí đủ lớn.
        if (delta >= 2) {
          _sessionDistanceMeters += delta;
          _modeDistanceMeters[_activityMode] =
              (_modeDistanceMeters[_activityMode] ?? 0) + delta;
          if (effectiveSpeed > 0) {
            _speedAccumulator += effectiveSpeed;
            _speedSamples += 1;
          }
          await _healthService.addStepsFromTrackedDistance(
            distanceMeters: delta,
            strideMeters: _adaptiveStrideMetersForMode(_activityMode, effectiveSpeed),
          );
        }
      }

      _previousPoint = nextPoint;
      _previousFixTime = now;
      if (!mounted) return;
      setState(() {
        _hasMapFix = true;
        _currentPoint = nextPoint;
        _path.add(nextPoint);
      });
      unawaited(_saveTodayPath());
      _moveMapToCurrent();
    });
  }

  double _adaptiveStrideMetersForMode(ActivityMode mode, double speedMps) {
    final speed = speedMps.clamp(0.0, 12.0);
    switch (mode) {
      case ActivityMode.walk:
        if (speed < 0.6) return 0.62;
        if (speed < 1.0) return 0.70;
        if (speed < 1.5) return 0.78;
        return 0.85;
      case ActivityMode.run:
        if (speed < 1.8) return 0.92;
        if (speed < 2.6) return 1.05;
        if (speed < 3.4) return 1.18;
        return 1.30;
      case ActivityMode.bike:
        if (speed < 3.0) return 2.3;
        if (speed < 5.0) return 2.8;
        if (speed < 7.0) return 3.3;
        return 3.8;
    }
  }

  Future<void> _saveFinishedSession() async {
    final startedAt = _sessionStartedAt;
    if (startedAt == null) return;

    final stepsDelta = (_todaySteps - _sessionStartSteps).clamp(0, 1000000);
    final avgSpeed = _speedSamples > 0 ? (_speedAccumulator / _speedSamples) : 0.0;
    final hasModeSwitch = _modeDistanceMeters.values.where((v) => v > 0).length > 1;

    final segments = <Map<String, dynamic>>[];
    _modeDistanceMeters.forEach((mode, meters) {
      if (meters <= 0) return;
      segments.add({
        'mode': _modeKey(mode),
        'distanceMeters': meters,
      });
    });

    final mode = hasModeSwitch ? 'mixed' : _modeKey(_activityMode);

    await _healthService.saveActivitySession(
      mode: mode,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      distanceMeters: _sessionDistanceMeters,
      stepsDelta: stepsDelta,
      avgSpeedMps: avgSpeed,
      segments: segments,
      sessionId: _activeSessionId,
      upsert: true,
    );
    _sessionStartedAt = null;
    _activeSessionId = null;
    await _saveTodayPath();
    await _loadActivitySummaries();
    await _loadRecentSessions();
  }

  void _startAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(_autoSaveInterval, (_) {
      if (!_isTracking) return;
      unawaited(_saveDraftSession());
    });
  }

  Future<void> _saveDraftSession() async {
    final startedAt = _sessionStartedAt;
    final sessionId = _activeSessionId;
    if (startedAt == null || sessionId == null) return;

    final stepsDelta = (_todaySteps - _sessionStartSteps).clamp(0, 1000000);
    final avgSpeed = _speedSamples > 0 ? (_speedAccumulator / _speedSamples) : 0.0;
    final hasModeSwitch = _modeDistanceMeters.values.where((v) => v > 0).length > 1;
    final segments = <Map<String, dynamic>>[];
    _modeDistanceMeters.forEach((mode, meters) {
      if (meters <= 0) return;
      segments.add({
        'mode': _modeKey(mode),
        'distanceMeters': meters,
      });
    });

    try {
      await _healthService.saveActivitySession(
        mode: hasModeSwitch ? 'mixed' : _modeKey(_activityMode),
        startedAt: startedAt,
        endedAt: DateTime.now(),
        distanceMeters: _sessionDistanceMeters,
        stepsDelta: stepsDelta,
        avgSpeedMps: avgSpeed,
        source: 'gps_tracking_autosave',
        segments: segments,
        sessionId: sessionId,
        upsert: true,
      );
      await _saveTodayPath();
      await _loadActivitySummaries();
    } catch (_) {
      // Keep autosave silent to avoid interrupting tracking UI.
    }
  }

  void _onModeSelected(ActivityMode mode) {
    if (_activityMode == mode) return;
    if (!mounted) return;
    setState(() {
      _activityMode = mode;
      if (mode != ActivityMode.bike) {
        _bikeSpeedWarningLevel = 0;
        _highSpeedStreak = 0;
      }
    });
  }

  String _modeKey(ActivityMode mode) {
    switch (mode) {
      case ActivityMode.walk:
        return 'walk';
      case ActivityMode.run:
        return 'run';
      case ActivityMode.bike:
        return 'bike';
    }
  }

  void _showSessionHistorySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121217),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        if (_recentSessions.isEmpty) {
          return const SizedBox(
            height: 220,
            child: Center(
              child: Text(
                'Chưa có phiên hoạt động nào.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          );
        }

        return SizedBox(
          height: 420,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemBuilder: (context, index) {
              final item = _recentSessions[index];
              final mode = (item['mode'] ?? 'walk').toString();
              final steps = (item['stepsDelta'] as num?)?.toInt() ?? 0;
              final distance = ((item['distanceMeters'] as num?)?.toDouble() ?? 0) / 1000;
              final durationSec = (item['durationSec'] as num?)?.toInt() ?? 0;
              final startedAt = DateTime.tryParse((item['startedAt'] ?? '').toString());

              return Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1B1C23),
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: _chipColorForMode(mode).withValues(alpha: 0.2),
                      child: Icon(_iconForMode(mode), color: _chipColorForMode(mode), size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _prettyMode(mode),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${distance.toStringAsFixed(2)} km • $steps bước • ${_formatDuration(durationSec)}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          if (startedAt != null)
                            Text(
                              _formatDateTime(startedAt),
                              style: const TextStyle(color: Colors.white38, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemCount: _recentSessions.length,
          ),
        );
      },
    );
  }

  String _formatDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  String _formatDateTime(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m $h:$min';
  }

  String _prettyMode(String mode) {
    switch (mode.toLowerCase()) {
      case 'mixed':
        return 'Mixed';
      case 'running':
      case 'run':
        return 'Running';
      case 'bike':
        return 'Bike';
      default:
        return 'Walk';
    }
  }

  IconData _iconForMode(String mode) {
    switch (mode.toLowerCase()) {
      case 'mixed':
        return Icons.swap_horiz_rounded;
      case 'running':
      case 'run':
        return Icons.directions_run;
      case 'bike':
        return Icons.directions_bike;
      default:
        return Icons.directions_walk;
    }
  }

  Color _chipColorForMode(String mode) {
    switch (mode.toLowerCase()) {
      case 'mixed':
        return const Color(0xFF8C8C8C);
      case 'running':
      case 'run':
        return const Color(0xFFEF8C3B);
      case 'bike':
        return const Color(0xFF6EA3D8);
      default:
        return const Color(0xFFCFAE85);
    }
  }
}

class _MapHintChip extends StatelessWidget {
  const _MapHintChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
