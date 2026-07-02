import 'package:flutter/material.dart';
import '../../models/beacon_model.dart';
import '../../services/admin_api_service.dart';
import '../../services/auth_service.dart';

class BeaconsScreen extends StatefulWidget {
  final bool canCreate;

  const BeaconsScreen({super.key, required this.canCreate});

  @override
  State<BeaconsScreen> createState() => _BeaconsScreenState();
}

class _BeaconFormData {
  final String? id;
  final String? roomId;
  final String uuid;
  final String? major;
  final String? minor;
  final String name;
  final String? advertiserType;
  final int? txPower;
  final double thresholdDistance;
  final bool isActive;

  _BeaconFormData({
    this.id,
    this.roomId,
    required this.uuid,
    this.major,
    this.minor,
    required this.name,
    this.advertiserType,
    this.txPower,
    required this.thresholdDistance,
    required this.isActive,
  });
}

class _BeaconsScreenState extends State<BeaconsScreen> {
  final AdminApiService _api = AdminApiService();
  final AuthService _authService = AuthService();

  bool _loading = true;
  String? _error;
  List<BeaconModel> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await _api.getBeacons();
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _nullableText(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<_BeaconFormData?> _showBeaconDialog({BeaconModel? beacon}) async {
    final isEdit = beacon != null;

    final idController = TextEditingController(text: beacon?.id ?? '');
    final roomIdController = TextEditingController(text: beacon?.roomId ?? '');
    final uuidController = TextEditingController(text: beacon?.uuid ?? '');
    final majorController = TextEditingController(text: beacon?.major ?? '1');
    final minorController = TextEditingController(text: beacon?.minor ?? '1');
    final nameController = TextEditingController(text: beacon?.name ?? '');
    final advertiserTypeController = TextEditingController(
      text: beacon?.advertiserType ?? 'ipad',
    );
    final txPowerController = TextEditingController(
      text: '${beacon?.txPower ?? -59}',
    );
    final thresholdController = TextEditingController(
      text: '${beacon?.thresholdDistance ?? 3.0}',
    );

    bool isActive = beacon?.isActive ?? true;

    final result = await showDialog<_BeaconFormData>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text(isEdit ? 'Beacon засах' : 'Шинэ beacon'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: idController,
                      enabled: !isEdit,
                      decoration: const InputDecoration(
                        labelText: 'Beacon ID',
                        helperText: 'Жишээ: BEA003',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: roomIdController,
                      decoration: const InputDecoration(
                        labelText: 'Room ID',
                        helperText: 'Жишээ: ROOM403',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: uuidController,
                      decoration: const InputDecoration(
                        labelText: 'UUID / Advertising name',
                        helperText:
                            'iPad advertiser дээр харагдаж байгаа яг нэрийг бичнэ',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: majorController,
                      decoration: const InputDecoration(labelText: 'Major'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: minorController,
                      decoration: const InputDecoration(labelText: 'Minor'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: advertiserTypeController,
                      decoration: const InputDecoration(
                        labelText: 'Advertiser Type',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: txPowerController,
                      decoration: const InputDecoration(labelText: 'Tx Power'),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: thresholdController,
                      decoration: const InputDecoration(
                        labelText: 'Threshold Distance',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    SwitchListTile(
                      value: isActive,
                      onChanged: (value) {
                        setLocalState(() => isActive = value);
                      },
                      title: const Text('Active'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Болих'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final uuid = uuidController.text.trim();
                    final name = nameController.text.trim();
                    final id = idController.text.trim();

                    if (!isEdit && id.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Beacon ID оруулна уу')),
                      );
                      return;
                    }
                    if (uuid.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('UUID / нэр оруулна уу')),
                      );
                      return;
                    }
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Name оруулна уу')),
                      );
                      return;
                    }

                    Navigator.pop(
                      context,
                      _BeaconFormData(
                        id: isEdit ? null : id,
                        roomId: _nullableText(roomIdController),
                        uuid: uuid,
                        major: _nullableText(majorController),
                        minor: _nullableText(minorController),
                        name: name,
                        advertiserType: _nullableText(advertiserTypeController),
                        txPower: int.tryParse(txPowerController.text.trim()),
                        thresholdDistance:
                            double.tryParse(thresholdController.text.trim()) ??
                            3.0,
                        isActive: isActive,
                      ),
                    );
                  },
                  child: const Text('Хадгалах'),
                ),
              ],
            );
          },
        );
      },
    );

    idController.dispose();
    roomIdController.dispose();
    uuidController.dispose();
    majorController.dispose();
    minorController.dispose();
    nameController.dispose();
    advertiserTypeController.dispose();
    txPowerController.dispose();
    thresholdController.dispose();

    return result;
  }

  Future<void> _showCreateDialog() async {
    final orgId = await _authService.getOrganizationId() ?? 'ORG001';
    if (!mounted) return;

    final data = await _showBeaconDialog();
    if (data == null) return;

    try {
      await _api.createBeacon(
        id: data.id!,
        organizationId: orgId,
        roomId: data.roomId,
        uuid: data.uuid,
        major: data.major,
        minor: data.minor,
        name: data.name,
        advertiserType: data.advertiserType,
        txPower: data.txPower,
        thresholdDistance: data.thresholdDistance,
        isActive: data.isActive,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Алдаа: $e')));
    }
  }

  Future<void> _showEditDialog(BeaconModel beacon) async {
    final data = await _showBeaconDialog(beacon: beacon);
    if (data == null) return;

    try {
      await _api.updateBeacon(
        beaconId: beacon.id,
        roomId: data.roomId,
        uuid: data.uuid,
        major: data.major,
        minor: data.minor,
        name: data.name,
        advertiserType: data.advertiserType,
        txPower: data.txPower,
        thresholdDistance: data.thresholdDistance,
        isActive: data.isActive,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Алдаа: $e')));
    }
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(child: Text('Алдаа: $_error'));
    }

    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 80, 16, 24),
          children: const [
            Icon(Icons.bluetooth_disabled_rounded, size: 56),
            SizedBox(height: 12),
            Center(
              child: Text(
                'Beacon олдсонгүй',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
            child: ListTile(
              leading: const Icon(Icons.bluetooth_searching_rounded),
              title: Text(item.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ID: ${item.id}'),
                  Text('UUID/name: ${item.uuid}'),
                  Text(
                    'Major/Minor: ${item.major ?? '-'} / ${item.minor ?? '-'}',
                  ),
                  Text('Threshold: ${item.thresholdDistance} m'),
                  Text('Room: ${item.roomId ?? '-'}'),
                  if (widget.canCreate)
                    const Text('Засахын тулд дээр нь дарна уу'),
                ],
              ),
              trailing: Chip(
                label: Text(item.isActive ? 'active' : 'inactive'),
              ),
              onTap: widget.canCreate ? () => _showEditDialog(item) : null,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      floatingActionButton:
          widget.canCreate
              ? FloatingActionButton(
                onPressed: _showCreateDialog,
                child: const Icon(Icons.add),
              )
              : null,
      body: _buildBody(),
    );
  }
}
