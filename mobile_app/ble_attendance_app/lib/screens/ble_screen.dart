import 'dart:async';

import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../core/utils/rssi_utils.dart';
import '../services/attendance_service.dart';
import '../services/auth_service.dart';
import '../services/ble_service.dart';
import '../services/notification_service.dart';
import '../services/active_session_service.dart';

enum AttendanceUiState {
  scanning,
  nearby,
  checkingIn,
  checkedIn,
  checkingOut,
  checkedOut,
  queuedOffline,
  error,
}

class BleScreen extends StatefulWidget {
  const BleScreen({super.key});

  @override
  State<BleScreen> createState() => _BleScreenState();
}

class _BleScreenState extends State<BleScreen>
    with SingleTickerProviderStateMixin {
  final BleService ble = BleService();
  final AttendanceService attendance = AttendanceService();
  final AuthService auth = AuthService();
  final NotificationService notifications = NotificationService();
  final ActiveSessionService activeSessionService = ActiveSessionService();

  List<BeaconTarget> dynamicTargets = [];
  bool _loadingActiveSessions = false;
  DateTime? _lastActiveSessionLoadAt;
  StreamSubscription<BleReading>? _readingSub;
  Timer? _syncTimer;
  Timer? _restartTimer;
  Timer? _scanHealthTimer;

  AttendanceUiState uiState = AttendanceUiState.scanning;

  String status = 'Скан хийж байна...';
  int rssi = 0;
  double distance = 0.0;

  bool isProcessing = false;
  bool isCheckedIn = false;

  int stableInCount = 0;
  int stableOutCount = 0;

  String? activeSessionId;
  BeaconTarget? activeTarget;
  BleReading? latestReading;

  // Тухайн session-д check-out хийсний дараа дахин ойртсон үед
  // дахин check-in request илгээхгүй хамгаална.
  final Set<String> _completedSessionIds = <String>{};

  bool _roleChecked = false;
  bool _canUseBle = false;
  String? _currentRole;

  DateTime? lastCheckInAt;
  DateTime? lastCheckOutAt;

  DateTime? _checkInBlockedUntil;
  DateTime? _lastCheckInErrorNotifiedAt;
  String? _lastCheckInErrorMessage;

  DateTime _lastUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  final List<int> rssiHistory = [];
  final List<int> rawRssiHistory = [];
  final List<double> distanceHistory = [];

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.97, end: 1.03).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initRoleAndScan();
  }

  Future<void> _loadActiveSessions({bool force = false}) async {
    if (_loadingActiveSessions) return;

    final now = DateTime.now();

    if (!force &&
        _lastActiveSessionLoadAt != null &&
        now.difference(_lastActiveSessionLoadAt!).inSeconds < 30) {
      return;
    }

    _loadingActiveSessions = true;

    try {
      final sessions = await activeSessionService.getActiveTodaySessions();

      final targets =
          sessions.map((s) {
            return BeaconTarget.fromActiveSession(
              beaconUuid: s.beaconUuid,
              sessionId: s.sessionId,
              roomName: s.roomName,
              major: s.major,
              minor: s.minor,
              thresholdDistance: s.thresholdDistance,
              minRssi: -80,
            );
          }).toList();

      if (!mounted) return;

      setState(() {
        dynamicTargets = targets;
        _lastActiveSessionLoadAt = DateTime.now();

        if (targets.isEmpty && !isCheckedIn && !isProcessing) {
          uiState = AttendanceUiState.scanning;
          status = 'Өнөөдрийн BLE session олдсонгүй';
        }
      });

      if (targets.isEmpty) {
        notifications.add(
          title: 'Өнөөдрийн session байхгүй',
          message: 'Өнөөдөр таны хуваарьт BLE ирц авах session олдсонгүй.',
          type: 'warning',
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _lastActiveSessionLoadAt = DateTime.now();

        dynamicTargets = [];

        if (!isCheckedIn && !isProcessing) {
          uiState = AttendanceUiState.error;
          status =
              'Session ачаалж чадсангүй. Beacon target байхгүй тул check-in хийхгүй.';
        }
      });

      notifications.add(
        title: 'Session ачаалах алдаа',
        message: e.toString().replaceFirst('Exception: ', ''),
        type: 'error',
      );
    } finally {
      _loadingActiveSessions = false;
    }
  }

  Future<void> _initRoleAndScan() async {
    final role = await auth.getRole() ?? 'student';
    final canUseBle = AppConfig.canUseBle(role);

    if (!mounted) return;

    setState(() {
      _currentRole = role;
      _canUseBle = canUseBle;
      _roleChecked = true;
    });

    if (!canUseBle) {
      setState(() {
        uiState = AttendanceUiState.error;
        status = 'Admin хэрэглэгч BLE check-in хийх боломжгүй.';
      });
      return;
    }

    Future.delayed(const Duration(milliseconds: 700), () async {
      if (mounted && _canUseBle) {
        await _loadActiveSessions(force: true);
        await _startScan();
      }
    });

    _syncTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (_canUseBle) {
        await _syncPending();
      }
    });

    _scanHealthTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      if (!mounted || !_canUseBle) return;

      await _loadActiveSessions();

      if (!ble.isScanning && uiState != AttendanceUiState.error) {
        await _startScan();
      }
    });
  }

  Future<void> _startScan() async {
    final role = await auth.getRole() ?? _currentRole ?? 'student';
    if (!AppConfig.canUseBle(role)) {
      if (mounted) {
        setState(() {
          uiState = AttendanceUiState.error;
          status = 'Admin хэрэглэгч BLE check-in хийх боломжгүй';
        });
      }
      return;
    }

    try {
      await ble.stopScan();
      await _readingSub?.cancel();

      await ble.startScan();

      if (mounted) {
        setState(() {
          uiState = AttendanceUiState.scanning;
          status = 'Скан хийж байна...';
        });
      }

      _readingSub = ble.readings.listen(
        (reading) async {
          if (reading.rssi < -95) return;

          latestReading = reading;

          if (dynamicTargets.isEmpty) {
            final now = DateTime.now();
            final shouldUpdateUi =
                now.difference(_lastUiUpdate).inMilliseconds >= 300;

            if (!isCheckedIn && !isProcessing && mounted && shouldUpdateUi) {
              _lastUiUpdate = now;
              setState(() {
                rssi = reading.rssi;
                distance = reading.distance;
                latestReading = reading;
                uiState = AttendanceUiState.scanning;
                status =
                    'Өнөөдрийн active BLE session / beacon target олдсонгүй';
                activeTarget = null;
                stableInCount = 0;
                stableOutCount = 0;
              });
            }
            return;
          }

          final matchedTarget = _findMatchedTarget(reading);

          final now = DateTime.now();
          final shouldUpdateUi =
              now.difference(_lastUiUpdate).inMilliseconds >= 300;

          if (matchedTarget == null) {
            if (!isCheckedIn && !isProcessing && mounted && shouldUpdateUi) {
              _lastUiUpdate = now;

              setState(() {
                rssi = reading.rssi;
                distance = reading.distance;
                latestReading = reading;
                uiState = AttendanceUiState.scanning;
                status = 'Скан хийж байна...';
                activeTarget = null;
                stableInCount = 0;
                stableOutCount = 0;
              });
            }
            return;
          }

          // Зөв beacon/session таарсан үед л RSSI sample болон chart-д нэмнэ.
          // Ингэснээр өөр BLE төхөөрөмжийн RSSI sample холилдохгүй.
          _appendCharts(reading);

          if (mounted && shouldUpdateUi) {
            _lastUiUpdate = now;

            setState(() {
              rssi = reading.rssi;
              distance = reading.distance;
              latestReading = reading;
              activeTarget = matchedTarget;
            });
          }

          if (_completedSessionIds.contains(matchedTarget.sessionId) &&
              !isCheckedIn &&
              !isProcessing) {
            stableInCount = 0;
            stableOutCount = 0;

            if (mounted && shouldUpdateUi) {
              setState(() {
                uiState = AttendanceUiState.checkedOut;
                status = '✅ Энэ хичээлд бүртгэгдсэн байна';
              });
            }
            return;
          }

          final dynamicThreshold = _dynamicThreshold(
            reading.rssi,
            matchedTarget,
          );

          final canCheckIn =
              !isCheckedIn &&
              !isProcessing &&
              reading.distance <= dynamicThreshold &&
              reading.rssi >= matchedTarget.minRssi;

          final canCheckOut =
              isCheckedIn &&
              !isProcessing &&
              _sameSession(activeSessionId, matchedTarget.sessionId) &&
              reading.distance >= matchedTarget.checkOutDistance;

          if (canCheckIn) {
            stableInCount++;
            stableOutCount = 0;

            if (mounted &&
                shouldUpdateUi &&
                uiState != AttendanceUiState.checkingIn &&
                uiState != AttendanceUiState.checkedIn) {
              setState(() {
                uiState = AttendanceUiState.nearby;
                status =
                    '📍 ${matchedTarget.roomName} ойр байна. Баталгаажуулж байна...';
              });
            }
          } else if (!isCheckedIn) {
            stableInCount = 0;
          }

          if (canCheckOut) {
            stableOutCount++;
          } else if (isCheckedIn) {
            stableOutCount = 0;
          }

          if (stableInCount >= AppConfig.stableInRequired) {
            stableInCount = 0;
            await _autoCheckIn(reading, matchedTarget);
          }

          if (stableOutCount >= AppConfig.stableOutRequired) {
            stableOutCount = 0;
            await _autoCheckOut(matchedTarget);
          }
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            uiState = AttendanceUiState.error;
            status = 'BLE уншихад алдаа: $e';
          });
          _scheduleRestart();
        },
        cancelOnError: false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        uiState = AttendanceUiState.error;
        status = 'Scan эхлүүлэхэд алдаа: $e';
      });
      _scheduleRestart();
    }
  }

  void _scheduleRestart() {
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(seconds: 3), () async {
      if (mounted) {
        await _startScan();
      }
    });
  }

  BeaconTarget? _findMatchedTarget(BleReading reading) {
    // Зөвхөн backend-ээс ирсэн өнөөдрийн active session-ийн beacon target-уудыг ашиглана.
    // Fallback target ашиглахгүй. Ингэснээр beacon асаагүй үед ойр байгаа
    // өөр BLE төхөөрөмжөөр check-in болохоос хамгаална.
    if (dynamicTargets.isEmpty) {
      return null;
    }

    for (final target in dynamicTargets) {
      final matched = ble.matchesTargetBeacon(
        reading: reading,
        targetText: target.beaconUuid,
      );

      if (matched) {
        return target;
      }
    }

    return null;
  }

  double _dynamicThreshold(int currentRssi, BeaconTarget target) {
    final adaptive = RssiUtils.adaptiveThresholdDistance(currentRssi);
    return adaptive < target.checkInDistance
        ? adaptive
        : target.checkInDistance;
  }

  bool _sameSession(String? actualSessionId, String targetSessionId) {
    if (actualSessionId == null || actualSessionId.isEmpty) return false;
    if (actualSessionId == targetSessionId) return true;
    return actualSessionId.startsWith('${targetSessionId}_');
  }

  Future<String> _resolveDeviceUuid() async {
    final userId = await auth.getUserId();

    if (userId == null || userId.isEmpty) {
      throw Exception('User ID олдсонгүй');
    }

    final role = await auth.getRole() ?? 'student';

    return AppConfig.deviceUuidForUser(userId: userId, role: role);
  }

  void _appendCharts(BleReading reading) {
    if (!reading.distance.isFinite ||
        reading.distance < 0 ||
        reading.distance > 100) {
      return;
    }

    if (reading.rssi < -110 || reading.rssi > -20) {
      return;
    }

    if (reading.rawRssi < -110 || reading.rawRssi > -20) {
      return;
    }

    // UI chart-д filtered RSSI ашиглана.
    rssiHistory.add(reading.rssi);

    // Backend anti-spoofing variance check-д raw RSSI sample ашиглана.
    rawRssiHistory.add(reading.rawRssi);

    distanceHistory.add(reading.distance);

    if (rssiHistory.length > 24) rssiHistory.removeAt(0);
    if (rawRssiHistory.length > 24) rawRssiHistory.removeAt(0);
    if (distanceHistory.length > 24) distanceHistory.removeAt(0);
  }

  List<int> _latestRssiSamples({int max = 8}) {
    final source = rawRssiHistory.isNotEmpty ? rawRssiHistory : rssiHistory;

    if (source.isEmpty) return [];

    if (source.length <= max) {
      return List<int>.from(source);
    }

    return List<int>.from(source.sublist(source.length - max));
  }

  bool _shouldNotifyCheckInError(String message) {
    final now = DateTime.now();

    if (_lastCheckInErrorMessage == message &&
        _lastCheckInErrorNotifiedAt != null &&
        now.difference(_lastCheckInErrorNotifiedAt!).inMinutes < 10) {
      return false;
    }

    _lastCheckInErrorMessage = message;
    _lastCheckInErrorNotifiedAt = now;
    return true;
  }

  Future<void> _autoCheckIn(BleReading reading, BeaconTarget target) async {
    if (isProcessing) return;
    if (isCheckedIn) return;

    final blockedUntil = _checkInBlockedUntil;
    if (blockedUntil != null && DateTime.now().isBefore(blockedUntil)) {
      return;
    }

    // activeSessionId нь backend-ээс буцсан daily session ID байж болно
    // (ж: SESSION002_20260513). Тиймээс template session ID-тэй prefix байдлаар
    // харьцуулж давхар check-in-ийг UI талд давхар хамгаална.
    if (activeSessionId == target.sessionId ||
        (activeSessionId?.startsWith('${target.sessionId}_') ?? false)) {
      return;
    }

    if (lastCheckInAt != null &&
        DateTime.now().difference(lastCheckInAt!) <
            AppConfig.duplicateCheckWindow) {
      return;
    }

    final samples = _latestRssiSamples(max: 8);

    // Backend ensure_ble_signal_quality() дор хаяж 3 RSSI sample шаарддаг.
    // 3 хүрээгүй үед request илгээхгүй, scan үргэлжлүүлнэ.
    if (samples.length < 3) {
      stableInCount = 0;
      if (mounted) {
        setState(() {
          uiState = AttendanceUiState.nearby;
          status = '📡 RSSI sample цуглуулж байна (${samples.length}/3)...';
        });
      }
      return;
    }

    // Backend RSSI average шалгалттай зөрүүлэхгүйн тулд
    // request-ийн үндсэн RSSI-г сүүлийн sample-уудын дунджаар явуулна.
    final requestRssi =
        (samples.reduce((a, b) => a + b) / samples.length).round();

    isProcessing = true;

    if (mounted) {
      setState(() {
        uiState = AttendanceUiState.checkingIn;
        status = '⏳ ${target.roomName} дээр check-in хийж байна...';
      });
    }

    try {
      final userId = await auth.getUserId();

      if (userId == null || userId.isEmpty) {
        throw Exception('User ID олдсонгүй');
      }

      final role = await auth.getRole() ?? 'student';
      if (!AppConfig.canUseBle(role)) {
        throw Exception('Admin хэрэглэгч BLE check-in хийх боломжгүй.');
      }

      final deviceUuid = await _resolveDeviceUuid();

      final result = await attendance.checkIn(
        userId: userId,
        sessionId: target.sessionId,
        deviceUuid: deviceUuid,
        beaconUuid: target.beaconUuid,
        major: target.major,
        minor: target.minor,
        // Backend RSSI average check-тэй зөрүүлэхгүйн тулд
        // сүүлийн sample-уудын дундаж RSSI-г явуулна.
        rssi: requestRssi,
        distance: reading.distance,
        rssiSamples: samples,
        note: 'BLE auto check-in @ ${target.roomName}',
      );

      final actualSessionId =
          result['session_id']?.toString() ?? target.sessionId;

      lastCheckInAt = DateTime.now();
      isCheckedIn = true;
      activeTarget = target;
      activeSessionId = actualSessionId;

      if (!mounted) return;

      if (result['already_checked_in'] == true) {
        setState(() {
          uiState = AttendanceUiState.checkedIn;
          status = '✅ Энэ хичээлд бүртгэгдсэн байна';
        });
      } else if (result['queued'] == true) {
        setState(() {
          uiState = AttendanceUiState.queuedOffline;
          status = '🟡 Offline queue-д хадгаллаа';
        });
      } else {
        setState(() {
          uiState = AttendanceUiState.checkedIn;
          status = '✅ ${target.roomName} дээр check-in амжилттай';
        });
      }

      notifications.add(
        title: 'Check-in',
        message: '${target.roomName} • ${activeSessionId ?? target.sessionId}',
        type: 'attendance',
      );
    } catch (e) {
      isCheckedIn = false;
      activeSessionId = null;

      final errorMessage = e.toString().replaceFirst('Exception: ', '');
      final isSessionTimeError = errorMessage.contains(
        'Session цагийн хүрээнээс гадуур',
      );

      if (isSessionTimeError) {
        // Session хаалттай/цагийн гадуур үед BLE ойрхон байгаа тул app байнга retry хийж
        // notification дүүргэдэг. Түр хугацаанд retry-г зогсооно.
        _checkInBlockedUntil = DateTime.now().add(const Duration(minutes: 10));
      }

      if (!mounted) return;

      setState(() {
        uiState =
            isSessionTimeError
                ? AttendanceUiState.scanning
                : AttendanceUiState.error;
        status =
            isSessionTimeError
                ? '⏰ Session цагийн хүрээнээс гадуур байна. 10 минутын дараа дахин шалгана.'
                : '❌ $errorMessage';
      });

      if (_shouldNotifyCheckInError(errorMessage)) {
        notifications.add(
          title: 'Check-in алдаа',
          message: errorMessage,
          type: 'error',
        );
      }
    } finally {
      isProcessing = false;
    }
  }

  Future<void> _autoCheckOut(BeaconTarget target) async {
    if (isProcessing || !isCheckedIn || activeSessionId == null) return;

    if (lastCheckOutAt != null &&
        DateTime.now().difference(lastCheckOutAt!) <
            AppConfig.duplicateCheckWindow) {
      return;
    }

    isProcessing = true;

    if (mounted) {
      setState(() {
        uiState = AttendanceUiState.checkingOut;
        status = '⏳ ${target.roomName} дээр check-out хийж байна...';
      });
    }

    try {
      final role = await auth.getRole() ?? 'student';
      if (!AppConfig.canUseBle(role)) {
        throw Exception('Admin хэрэглэгч BLE check-out хийх боломжгүй.');
      }

      final deviceUuid = await _resolveDeviceUuid();

      final checkedOutSessionId = activeSessionId!;

      final result = await attendance.checkOut(
        sessionId: checkedOutSessionId,
        deviceUuid: deviceUuid,
        note: 'BLE auto check-out @ ${target.roomName}',
      );

      lastCheckOutAt = DateTime.now();
      _completedSessionIds.add(checkedOutSessionId);
      // Template session ID хэлбэрээр бас хадгална.
      _completedSessionIds.add(target.sessionId);

      isCheckedIn = false;
      activeSessionId = null;

      if (!mounted) return;

      if (result['already_checked_out'] == true) {
        setState(() {
          uiState = AttendanceUiState.checkedOut;
          status = '✅ Аль хэдийн check-out бүртгэгдсэн байна';
        });
      } else if (result['queued'] == true) {
        setState(() {
          uiState = AttendanceUiState.queuedOffline;
          status = '🟡 Offline check-out queue-д хадгаллаа';
        });
      } else {
        setState(() {
          uiState = AttendanceUiState.checkedOut;
          status = '✅ ${target.roomName} дээр check-out амжилттай';
        });
      }

      notifications.add(
        title: 'Check-out',
        message: '${target.roomName} • $checkedOutSessionId',
        type: 'attendance',
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        uiState = AttendanceUiState.error;
        status = '❌ $e';
      });

      notifications.add(
        title: 'Check-out алдаа',
        message: e.toString(),
        type: 'error',
      );
    } finally {
      isProcessing = false;
    }
  }

  Future<void> _syncPending() async {
    try {
      final synced = await attendance.syncPendingAttendances();

      if (synced > 0) {
        notifications.add(
          title: 'Sync амжилттай',
          message: '$synced pending attendance sync хийгдлээ',
          type: 'success',
        );
      }

      if (mounted) setState(() {});
    } catch (_) {}
  }

  Color getStateColor() {
    switch (uiState) {
      case AttendanceUiState.scanning:
        return Colors.blue;
      case AttendanceUiState.nearby:
        return Colors.orange;
      case AttendanceUiState.checkingIn:
      case AttendanceUiState.checkingOut:
        return Colors.amber;
      case AttendanceUiState.checkedIn:
        return Colors.green;
      case AttendanceUiState.checkedOut:
        return Colors.teal;
      case AttendanceUiState.queuedOffline:
        return Colors.deepOrange;
      case AttendanceUiState.error:
        return Colors.red;
    }
  }

  IconData getStateIcon() {
    switch (uiState) {
      case AttendanceUiState.scanning:
        return Icons.bluetooth_searching;
      case AttendanceUiState.nearby:
        return Icons.location_searching;
      case AttendanceUiState.checkingIn:
        return Icons.login;
      case AttendanceUiState.checkingOut:
        return Icons.logout;
      case AttendanceUiState.checkedIn:
        return Icons.verified;
      case AttendanceUiState.checkedOut:
        return Icons.task_alt;
      case AttendanceUiState.queuedOffline:
        return Icons.cloud_off;
      case AttendanceUiState.error:
        return Icons.error;
    }
  }

  String getStateLabel() {
    switch (uiState) {
      case AttendanceUiState.scanning:
        return 'SCANNING';
      case AttendanceUiState.nearby:
        return 'NEARBY';
      case AttendanceUiState.checkingIn:
        return 'CHECKING-IN';
      case AttendanceUiState.checkingOut:
        return 'CHECKING-OUT';
      case AttendanceUiState.checkedIn:
        return 'CHECKED-IN';
      case AttendanceUiState.checkedOut:
        return 'CHECKED-OUT';
      case AttendanceUiState.queuedOffline:
        return 'OFFLINE-QUEUED';
      case AttendanceUiState.error:
        return 'ERROR';
    }
  }

  Widget _metricTile({
    required IconData icon,
    required String label,
    required String value,
    Color? color,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(label),
      trailing: SizedBox(
        width: 150,
        child: Text(
          value,
          textAlign: TextAlign.end,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildMiniChart(List<num> values, Color color) {
    if (values.isEmpty || values.length < 2) {
      return SizedBox(
        height: 60,
        width: double.infinity,
        child: Center(
          child: Text(
            'өгөгдөл цугларч байна...',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ),
      );
    }

    final safeValues =
        values.where((e) => e.isFinite).map((e) => e.toDouble()).toList();

    if (safeValues.length < 2) {
      return const SizedBox(height: 60, width: double.infinity);
    }

    final min = safeValues.reduce((a, b) => a < b ? a : b);
    final max = safeValues.reduce((a, b) => a > b ? a : b);
    final range = (max - min).abs() < 0.0001 ? 1.0 : (max - min);

    return SizedBox(
      height: 60,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CustomPaint(
          painter: _LineChartPainter(
            values: safeValues,
            color: color,
            min: min,
            range: range,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _restartTimer?.cancel();
    _syncTimer?.cancel();
    _scanHealthTimer?.cancel();
    _readingSub?.cancel();
    ble.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Widget _buildBleForbiddenView(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: cs.error.withValues(alpha: 0.12),
                  child: Icon(
                    Icons.admin_panel_settings_rounded,
                    color: cs.error,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Admin хэрэглэгч BLE check-in хийх боломжгүй.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'BLE ирц бүртгэл нь зөвхөн Student болон Teacher эрхтэй хэрэглэгчдэд нээлттэй.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_roleChecked) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_canUseBle) {
      return _buildBleForbiddenView(context);
    }

    final stateColor = getStateColor();
    final cs = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: _syncPending,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ScaleTransition(
            scale: _pulseAnimation,
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    colors: [
                      stateColor.withValues(alpha: 0.10),
                      stateColor.withValues(alpha: 0.04),
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: stateColor.withValues(alpha: 0.14),
                      child: Icon(getStateIcon(), color: stateColor, size: 34),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      getStateLabel(),
                      style: TextStyle(
                        color: stateColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      status,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Signal metrics',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  _metricTile(
                    icon: Icons.network_ping,
                    label: 'RSSI',
                    value: '$rssi dBm',
                    color: Colors.blue,
                  ),
                  _metricTile(
                    icon: Icons.straighten,
                    label: 'Distance',
                    value: '${distance.toStringAsFixed(2)} m',
                    color: Colors.green,
                  ),
                  _metricTile(
                    icon: Icons.devices,
                    label: 'Detected device',
                    value: latestReading?.deviceName ?? '-',
                    color: Colors.indigo,
                  ),
                  _metricTile(
                    icon: Icons.meeting_room_outlined,
                    label: 'Active room',
                    value: activeTarget?.roomName ?? '-',
                    color: Colors.orange,
                  ),
                  _metricTile(
                    icon: Icons.class_outlined,
                    label: 'Active session',
                    value: activeSessionId ?? '-',
                    color: Colors.purple,
                  ),
                  _metricTile(
                    icon: Icons.pin_outlined,
                    label: 'Stable in / out',
                    value: '$stableInCount / $stableOutCount',
                    color: Colors.teal,
                  ),
                  _metricTile(
                    icon: Icons.analytics_outlined,
                    label: 'RSSI samples',
                    value: '${_latestRssiSamples(max: 8).length}',
                    color: Colors.deepPurple,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Live RSSI график',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  _buildMiniChart(rssiHistory, Colors.blue),
                  const SizedBox(height: 18),
                  const Text(
                    'Distance график',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  _buildMiniChart(distanceHistory, Colors.green),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final double min;
  final double range;

  _LineChartPainter({
    required this.values,
    required this.color,
    required this.min,
    required this.range,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 ||
        size.width <= 0 ||
        size.height <= 0 ||
        !min.isFinite ||
        !range.isFinite ||
        range <= 0) {
      return;
    }

    final gridPaint =
        Paint()
          ..color = Colors.black.withValues(alpha: 0.05)
          ..strokeWidth = 1;

    for (int i = 1; i <= 2; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final linePaint =
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

    final fillPaint =
        Paint()
          ..color = color.withValues(alpha: 0.10)
          ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < values.length; i++) {
      final x = (i / (values.length - 1)) * size.width;
      final normalized = ((values[i] - min) / range).clamp(0.0, 1.0);
      final y = size.height - (normalized * size.height);

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }

      if (i == values.length - 1) {
        fillPath.lineTo(x, size.height);
        fillPath.close();
      }
    }

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.color != color ||
        oldDelegate.min != min ||
        oldDelegate.range != range;
  }
}
