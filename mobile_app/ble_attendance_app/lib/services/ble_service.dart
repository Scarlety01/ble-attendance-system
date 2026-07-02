import 'dart:async';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/utils/rssi_kalman.dart';
import '../core/utils/rssi_utils.dart';

class BleReading {
  final String deviceId;
  final String deviceName;

  /// Kalman filter-ээр тогтворжуулсан RSSI.
  /// UI болон distance тооцоололд ашиглана.
  final int rssi;

  /// Beacon-оос шууд ирсэн raw RSSI.
  /// Backend-ийн RSSI variance / anti-spoofing шалгалтад ашиглана.
  final int rawRssi;

  final double distance;
  final DateTime detectedAt;
  final List<String> serviceUuids;
  final String rawAdvName;
  final String rawPlatformName;

  BleReading({
    required this.deviceId,
    required this.deviceName,
    required this.rssi,
    required this.rawRssi,
    required this.distance,
    required this.detectedAt,
    required this.serviceUuids,
    required this.rawAdvName,
    required this.rawPlatformName,
  });
}

class BleService {
  final StreamController<BleReading> _controller =
      StreamController<BleReading>.broadcast();

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _isScanningSub;

  final Map<String, KalmanFilter> _filters = {};

  bool _isScanning = false;
  bool _disposed = false;

  Stream<BleReading> get readings => _controller.stream;
  bool get isScanning => _isScanning;

  Future<bool> requestPermissions() async {
    if (Platform.isIOS) {
      final bluetooth = await Permission.bluetooth.request();
      final location = await Permission.locationWhenInUse.request();

      return (bluetooth.isGranted || bluetooth.isLimited) &&
          (location.isGranted || location.isLimited);
    }

    if (Platform.isAndroid) {
      final bluetoothScan = await Permission.bluetoothScan.request();
      final bluetoothConnect = await Permission.bluetoothConnect.request();
      final location = await Permission.locationWhenInUse.request();

      return bluetoothScan.isGranted &&
          bluetoothConnect.isGranted &&
          location.isGranted;
    }

    return false;
  }

  Future<bool> ensureBluetoothOn() async {
    final state =
        await FlutterBluePlus.adapterState
            .where((s) => s != BluetoothAdapterState.unknown)
            .first;

    return state == BluetoothAdapterState.on;
  }

  int _kalmanRssi(String deviceKey, int rawRssi) {
    final filter = _filters.putIfAbsent(
      deviceKey,
      () => KalmanFilter(x: rawRssi.toDouble()),
    );

    return filter.update(rawRssi.toDouble()).round();
  }

  bool matchesTargetBeacon({
    required BleReading reading,
    required String targetText,
  }) {
    final target = targetText.toLowerCase().trim();
    if (target.isEmpty) return false;

    String normalize(String value) {
      return value.toLowerCase().trim().replaceAll('{', '').replaceAll('}', '');
    }

    final normalizedTarget = normalize(target);
    final adv = normalize(reading.rawAdvName);
    final name = normalize(reading.deviceName);
    final platform = normalize(reading.rawPlatformName);

    final serviceMatch = reading.serviceUuids.any((uuid) {
      return normalize(uuid) == normalizedTarget;
    });

    // STRICT MATCH:
    // Beacon унтраалттай үед ойр байгаа өөр Bluetooth төхөөрөмжийг
    // contains() нөхцлөөр андуурч match хийхээс хамгаална.
    // Тиймээс зөвхөн exact advertising name / platform name /
    // service UUID таарсан үед л тухайн beacon гэж үзнэ.
    return adv == normalizedTarget ||
        name == normalizedTarget ||
        platform == normalizedTarget ||
        serviceMatch;
  }

  Future<void> startScan() async {
    if (_disposed) return;

    final granted = await requestPermissions();
    if (!granted) {
      throw Exception('BLE permission зөвшөөрөгдөөгүй');
    }

    final isOn = await ensureBluetoothOn();
    if (!isOn) {
      throw Exception('Bluetooth асаалттай биш байна');
    }

    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    await _isScanningSub?.cancel();

    _isScanning = false;

    _isScanningSub = FlutterBluePlus.isScanning.listen((value) {
      _isScanning = value;
    });

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final device = result.device;
        final deviceId = device.remoteId.str;

        final advName = result.advertisementData.advName;
        final platformName = device.platformName;

        final uuids =
            result.advertisementData.serviceUuids
                .map((e) => e.toString())
                .toList();

        final rawRssi = result.rssi;

        // iOS/Android дээр заримдаа 127 зэрэг invalid RSSI ирдэг.
        // Backend validation нь RSSI-г -110..-20 хооронд хүлээн авдаг.
        if (rawRssi < -110 || rawRssi > -20) {
          continue;
        }

        final filteredRssi = _kalmanRssi(deviceId, rawRssi);

        // Kalman filter-ийн дараа ч хүрээнээс гарвал тухайн уншилтыг ашиглахгүй.
        if (filteredRssi < -110 || filteredRssi > -20) {
          continue;
        }

        final distance = RssiUtils.estimateDistance(rssi: filteredRssi);

        // Distance буруу эсвэл хэт их утга бол backend рүү явуулахгүй.
        if (!distance.isFinite || distance < 0 || distance > 100) {
          continue;
        }

        final displayName =
            advName.isNotEmpty
                ? advName
                : platformName.isNotEmpty
                ? platformName
                : deviceId;

        if (!_controller.isClosed) {
          _controller.add(
            BleReading(
              deviceId: deviceId,
              deviceName: displayName,
              rssi: filteredRssi,
              rawRssi: rawRssi,
              distance: distance,
              detectedAt: DateTime.now(),
              serviceUuids: uuids,
              rawAdvName: advName,
              rawPlatformName: platformName,
            ),
          );
        }
      }
    });

    // Continuous scan:
    // Өмнөх timeout: 10 секундийг авсан.
    // Ингэснээр BLE scan өөрөө 10 сек дараа автоматаар зогсохгүй.
    await FlutterBluePlus.startScan(androidUsesFineLocation: true);

    _isScanning = true;
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    await _scanSub?.cancel();
    await _isScanningSub?.cancel();

    _scanSub = null;
    _isScanningSub = null;
    _isScanning = false;
  }

  Future<void> dispose() async {
    _disposed = true;
    await stopScan();
    await _controller.close();
  }
}
