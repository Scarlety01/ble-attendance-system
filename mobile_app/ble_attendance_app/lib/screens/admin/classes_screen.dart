import 'package:flutter/material.dart';

import '../../models/class_model.dart';
import '../../models/class_student_model.dart';
import '../../services/admin_api_service.dart';

class ClassesScreen extends StatefulWidget {
  final bool canCreate;

  const ClassesScreen({super.key, required this.canCreate});

  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> {
  final AdminApiService _adminService = AdminApiService();

  final TextEditingController _searchController = TextEditingController();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _idController = TextEditingController();
  final TextEditingController _organizationIdController = TextEditingController(
    text: 'ORG001',
  );
  final TextEditingController _departmentIdController = TextEditingController(
    text: 'DEP001',
  );
  final TextEditingController _teacherIdController = TextEditingController(
    text: 'TEACH001',
  );
  final TextEditingController _roomIdController = TextEditingController(
    text: 'ROOM402',
  );
  final TextEditingController _beaconIdController = TextEditingController(
    text: 'BEA002',
  );
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _dayOfWeekController = TextEditingController(
    text: 'Monday',
  );
  final TextEditingController _startTimeController = TextEditingController(
    text: '09:00',
  );
  final TextEditingController _endTimeController = TextEditingController(
    text: '10:30',
  );
  final TextEditingController _lateAfterMinutesController =
      TextEditingController(text: '10');

  DateTime? _semesterStartDate;
  DateTime? _semesterEndDate;

  bool _isActive = true;
  String _type = 'class';

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _searchText = '';

  List<ClassModel> _classes = [];

  @override
  void initState() {
    super.initState();

    _loadClasses();

    _searchController.addListener(() {
      setState(() {
        _searchText = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();

    _idController.dispose();
    _organizationIdController.dispose();
    _departmentIdController.dispose();
    _teacherIdController.dispose();
    _roomIdController.dispose();
    _beaconIdController.dispose();
    _nameController.dispose();
    _codeController.dispose();
    _dayOfWeekController.dispose();
    _startTimeController.dispose();
    _endTimeController.dispose();
    _lateAfterMinutesController.dispose();

    super.dispose();
  }

  Future<void> _loadClasses() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await _adminService.getClasses();

      items.sort((a, b) => a.id.compareTo(b.id));

      if (!mounted) return;

      setState(() {
        _classes = items;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<ClassModel> get _filteredClasses {
    if (_searchText.isEmpty) return _classes;

    return _classes.where((item) {
      final text =
          [
            item.id,
            item.name,
            item.code,
            item.teacherId,
            item.roomId,
            item.beaconId,
            item.dayOfWeek,
            item.startTime,
            item.endTime,
            item.semesterStartDate,
            item.semesterEndDate,
          ].whereType<String>().join(' ').toLowerCase();

      return text.contains(_searchText);
    }).toList();
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Заавал бөглөнө үү';
    }
    return null;
  }

  String? _timeValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final valid = RegExp(r'^\d{2}:\d{2}$').hasMatch(value.trim());
    if (!valid) {
      return 'HH:mm форматаар оруулна уу';
    }

    final parts = value.trim().split(':');
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);

    if (hour == null || minute == null) {
      return 'Цаг буруу байна';
    }

    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return 'Цагийн утга буруу байна';
    }

    return null;
  }

  String? _dateToApi(DateTime? value) {
    if (value == null) return null;

    return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }

  DateTime? _parseApiDate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return DateTime.tryParse(value);
  }

  String _displayDate(String? value) {
    if (value == null || value.trim().isEmpty) return '-';
    return value;
  }

  Future<void> _pickSemesterStartDate(StateSetter setModalState) async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: _semesterStartDate ?? now,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(2035, 12, 31),
      helpText: 'Семестр эхлэх огноо',
      cancelText: 'Болих',
      confirmText: 'Сонгох',
    );

    if (picked != null) {
      setState(() => _semesterStartDate = picked);
      setModalState(() {});
    }
  }

  Future<void> _pickSemesterEndDate(StateSetter setModalState) async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: _semesterEndDate ?? _semesterStartDate ?? now,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(2035, 12, 31),
      helpText: 'Семестр дуусах огноо',
      cancelText: 'Болих',
      confirmText: 'Сонгох',
    );

    if (picked != null) {
      setState(() => _semesterEndDate = picked);
      setModalState(() {});
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();

    _idController.clear();
    _organizationIdController.text = 'ORG001';
    _departmentIdController.text = 'DEP001';
    _teacherIdController.text = 'TEACH001';
    _roomIdController.text = 'ROOM402';
    _beaconIdController.text = 'BEA002';
    _nameController.clear();
    _codeController.clear();
    _dayOfWeekController.text = 'Monday';
    _startTimeController.text = '09:00';
    _endTimeController.text = '10:30';
    _lateAfterMinutesController.text = '10';

    _semesterStartDate = null;
    _semesterEndDate = null;

    _isActive = true;
    _type = 'class';
  }

  void _fillFormForEdit(ClassModel item) {
    _idController.text = item.id;
    _organizationIdController.text = item.organizationId;
    _departmentIdController.text = item.departmentId;
    _teacherIdController.text = item.teacherId ?? '';
    _roomIdController.text = item.roomId ?? '';
    _beaconIdController.text = item.beaconId ?? '';
    _nameController.text = item.name;
    _codeController.text = item.code ?? '';
    _dayOfWeekController.text = item.dayOfWeek ?? 'Monday';
    _startTimeController.text = item.startTime ?? '';
    _endTimeController.text = item.endTime ?? '';
    _lateAfterMinutesController.text = item.lateAfterMinutes.toString();

    _semesterStartDate = _parseApiDate(item.semesterStartDate);
    _semesterEndDate = _parseApiDate(item.semesterEndDate);

    _isActive = item.isActive;
    _type = item.type;
  }

  Future<void> _openClassForm({ClassModel? item}) async {
    final isEdit = item != null;

    if (isEdit) {
      _fillFormForEdit(item);
    } else {
      _resetForm();
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final cs = Theme.of(context).colorScheme;
            final bottom = MediaQuery.of(context).viewInsets.bottom;

            return Material(
              color: cs.surface,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: bottom + 16,
                ),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      Text(
                        isEdit ? 'Хичээл засах' : 'Шинэ хичээл нэмэх',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 16),

                      _buildTextField(
                        controller: _idController,
                        label: 'Class ID',
                        hintText: 'CLASS004',
                        validator: _requiredValidator,
                        enabled: !isEdit,
                      ),
                      const SizedBox(height: 12),

                      _buildTextField(
                        controller: _organizationIdController,
                        label: 'Organization ID',
                        hintText: 'ORG001',
                        validator: _requiredValidator,
                        enabled: !isEdit,
                      ),
                      const SizedBox(height: 12),

                      _buildTextField(
                        controller: _departmentIdController,
                        label: 'Department ID',
                        hintText: 'DEP001',
                        validator: _requiredValidator,
                        enabled: !isEdit,
                      ),
                      const SizedBox(height: 12),

                      _buildTextField(
                        controller: _nameController,
                        label: 'Хичээлийн нэр',
                        hintText: 'Mobile Programming',
                        validator: _requiredValidator,
                      ),
                      const SizedBox(height: 12),

                      _buildTextField(
                        controller: _codeController,
                        label: 'Code',
                        hintText: 'SW401',
                      ),
                      const SizedBox(height: 12),

                      DropdownButtonFormField<String>(
                        value: _type,
                        decoration: const InputDecoration(
                          labelText: 'Type',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'class',
                            child: Text('class'),
                          ),
                          DropdownMenuItem(
                            value: 'shift',
                            child: Text('shift'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setModalState(() => _type = value);
                        },
                      ),
                      const SizedBox(height: 12),

                      _buildTextField(
                        controller: _teacherIdController,
                        label: 'Teacher ID',
                        hintText: 'TEACH001',
                      ),
                      const SizedBox(height: 12),

                      _buildTextField(
                        controller: _roomIdController,
                        label: 'Room ID',
                        hintText: 'ROOM402',
                      ),
                      const SizedBox(height: 12),

                      _buildTextField(
                        controller: _beaconIdController,
                        label: 'Beacon ID',
                        hintText: 'BEA002',
                      ),
                      const SizedBox(height: 12),

                      _buildDayPicker(setModalState),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _startTimeController,
                              label: 'Эхлэх цаг',
                              hintText: '09:00',
                              validator: _timeValidator,
                              keyboardType: TextInputType.datetime,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTextField(
                              controller: _endTimeController,
                              label: 'Дуусах цаг',
                              hintText: '10:30',
                              validator: _timeValidator,
                              keyboardType: TextInputType.datetime,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(
                            color: cs.outlineVariant.withOpacity(0.45),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          child: Column(
                            children: [
                              _semesterDateTile(
                                title: 'Семестр эхлэх огноо',
                                value: _semesterStartDate,
                                onTap:
                                    () => _pickSemesterStartDate(setModalState),
                              ),
                              const Divider(height: 1),
                              _semesterDateTile(
                                title: 'Семестр дуусах огноо',
                                value: _semesterEndDate,
                                onTap:
                                    () => _pickSemesterEndDate(setModalState),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      _buildTextField(
                        controller: _lateAfterMinutesController,
                        label: 'Хоцролт тооцох минут',
                        hintText: '10',
                        keyboardType: TextInputType.number,
                        validator: _requiredValidator,
                      ),
                      const SizedBox(height: 12),

                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Идэвхтэй'),
                        subtitle: Text(_isActive ? 'Active' : 'Inactive'),
                        value: _isActive,
                        onChanged: (value) {
                          setModalState(() => _isActive = value);
                        },
                      ),

                      const SizedBox(height: 18),

                      FilledButton.icon(
                        onPressed:
                            _saving
                                ? null
                                : () async {
                                  await _saveClass(
                                    isEdit: isEdit,
                                    item: item,
                                    setModalState: setModalState,
                                  );
                                },
                        icon:
                            _saving
                                ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Icon(Icons.save_rounded),
                        label: Text(
                          _saving
                              ? 'Хадгалж байна...'
                              : isEdit
                              ? 'Өөрчлөлт хадгалах'
                              : 'Хичээл нэмэх',
                        ),
                      ),

                      const SizedBox(height: 10),

                      OutlinedButton(
                        onPressed:
                            _saving
                                ? null
                                : () {
                                  Navigator.pop(context);
                                },
                        child: const Text('Болих'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveClass({
    required bool isEdit,
    required ClassModel? item,
    required StateSetter setModalState,
  }) async {
    if (!_formKey.currentState!.validate()) return;

    final lateMinutes =
        int.tryParse(_lateAfterMinutesController.text.trim()) ?? 10;

    if (_semesterStartDate != null &&
        _semesterEndDate != null &&
        _semesterEndDate!.isBefore(_semesterStartDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Семестр дуусах огноо эхлэх огнооноос өмнө байж болохгүй',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    setModalState(() {});

    try {
      if (isEdit) {
        await _adminService.updateClass(
          classId: item!.id,
          teacherId: _nullableText(_teacherIdController),
          roomId: _nullableText(_roomIdController),
          beaconId: _nullableText(_beaconIdController),
          name: _nameController.text.trim(),
          code: _nullableText(_codeController),
          type: _type,
          dayOfWeek: _nullableText(_dayOfWeekController),
          startTime: _nullableText(_startTimeController),
          endTime: _nullableText(_endTimeController),
          semesterStartDate: _dateToApi(_semesterStartDate),
          semesterEndDate: _dateToApi(_semesterEndDate),
          lateAfterMinutes: lateMinutes,
          isActive: _isActive,
        );
      } else {
        await _adminService.createClass(
          id: _idController.text.trim(),
          organizationId: _organizationIdController.text.trim(),
          departmentId: _departmentIdController.text.trim(),
          teacherId: _nullableText(_teacherIdController),
          roomId: _nullableText(_roomIdController),
          beaconId: _nullableText(_beaconIdController),
          name: _nameController.text.trim(),
          code: _nullableText(_codeController),
          type: _type,
          dayOfWeek: _nullableText(_dayOfWeekController),
          startTime: _nullableText(_startTimeController),
          endTime: _nullableText(_endTimeController),
          semesterStartDate: _dateToApi(_semesterStartDate),
          semesterEndDate: _dateToApi(_semesterEndDate),
          lateAfterMinutes: lateMinutes,
          isActive: _isActive,
        );
      }

      if (!mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEdit ? 'Хичээл шинэчлэгдлээ' : 'Хичээл нэмэгдлээ'),
        ),
      );

      await _loadClasses();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Хадгалах үед алдаа: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        setModalState(() {});
      }
    }
  }

  String? _nullableText(TextEditingController controller) {
    final value = controller.text.trim();
    if (value.isEmpty) return null;
    return value;
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hintText,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      validator: validator,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _buildDayPicker(StateSetter setModalState) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    final current =
        days.contains(_dayOfWeekController.text.trim())
            ? _dayOfWeekController.text.trim()
            : 'Monday';

    return DropdownButtonFormField<String>(
      value: current,
      decoration: InputDecoration(
        labelText: 'Гараг',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      items: const [
        DropdownMenuItem(value: 'Monday', child: Text('Даваа / Monday')),
        DropdownMenuItem(value: 'Tuesday', child: Text('Мягмар / Tuesday')),
        DropdownMenuItem(value: 'Wednesday', child: Text('Лхагва / Wednesday')),
        DropdownMenuItem(value: 'Thursday', child: Text('Пүрэв / Thursday')),
        DropdownMenuItem(value: 'Friday', child: Text('Баасан / Friday')),
        DropdownMenuItem(value: 'Saturday', child: Text('Бямба / Saturday')),
        DropdownMenuItem(value: 'Sunday', child: Text('Ням / Sunday')),
      ],
      onChanged: (value) {
        if (value == null) return;
        _dayOfWeekController.text = value;
        setModalState(() {});
      },
    );
  }

  Widget _semesterDateTile({
    required String title,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(value == null ? 'Сонгоогүй' : _dateToApi(value)!),
      trailing: const Icon(Icons.calendar_month_rounded),
      onTap: onTap,
    );
  }

  Future<void> _openStudentsSheet(ClassModel item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder:
          (_) =>
              _ClassStudentsSheet(classItem: item, adminService: _adminService),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: cs.primaryContainer,
            child: Icon(Icons.class_rounded, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Classes',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 2),
                Text('Хичээл, семестрийн хуваарь удирдах'),
              ],
            ),
          ),
          if (widget.canCreate)
            FilledButton.icon(
              onPressed: () => _openClassForm(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add'),
            ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: SearchBar(
        controller: _searchController,
        hintText: 'Хичээл хайх',
        leading: const Icon(Icons.search_rounded),
        trailing:
            _searchText.isNotEmpty
                ? [
                  IconButton(
                    onPressed: () {
                      _searchController.clear();
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ]
                : null,
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Expanded(child: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 48),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _loadClasses,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Дахин ачаалах'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final items = _filteredClasses;

    if (items.isEmpty) {
      return Expanded(
        child: RefreshIndicator(
          onRefresh: _loadClasses,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 120),
              Icon(Icons.class_outlined, size: 56),
              SizedBox(height: 12),
              Center(
                child: Text(
                  'Хичээл олдсонгүй',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Expanded(
      child: RefreshIndicator(
        onRefresh: _loadClasses,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];

            return _ClassCard(
              item: item,
              canEdit: widget.canCreate,
              onEdit: () => _openClassForm(item: item),
              onStudents: () => _openStudentsSheet(item),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surface,
      child: Column(
        children: [_buildHeader(context), _buildSearch(), _buildBody()],
      ),
    );
  }
}

class _ClassCard extends StatelessWidget {
  final ClassModel item;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onStudents;

  const _ClassCard({
    required this.item,
    required this.canEdit,
    required this.onEdit,
    required this.onStudents,
  });

  String _value(String? value) {
    if (value == null || value.trim().isEmpty) return '-';
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final statusColor = item.isActive ? cs.primary : cs.error;
    final statusText = item.isActive ? 'Active' : 'Inactive';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: cs.primaryContainer,
                  child: Icon(
                    Icons.school_rounded,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${item.id} • ${_value(item.code)}',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icon: Icons.person_rounded,
                  label: 'Teacher: ${_value(item.teacherId)}',
                ),
                _InfoChip(
                  icon: Icons.meeting_room_rounded,
                  label: 'Room: ${_value(item.roomId)}',
                ),
                _InfoChip(
                  icon: Icons.bluetooth_rounded,
                  label: 'Beacon: ${_value(item.beaconId)}',
                ),
                _InfoChip(
                  icon: Icons.calendar_today_rounded,
                  label:
                      '${_value(item.dayOfWeek)} ${_value(item.startTime)}-${_value(item.endTime)}',
                ),
                _InfoChip(
                  icon: Icons.date_range_rounded,
                  label:
                      '${_value(item.semesterStartDate)} → ${_value(item.semesterEndDate)}',
                ),
                _InfoChip(
                  icon: Icons.timer_rounded,
                  label: 'Late: ${item.lateAfterMinutes} мин',
                ),
              ],
            ),

            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onStudents,
                    icon: const Icon(Icons.group_rounded),
                    label: const Text('Students'),
                  ),
                ),
                if (canEdit) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_rounded),
                      label: const Text('Edit'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.7),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _ClassStudentsSheet extends StatefulWidget {
  final ClassModel classItem;
  final AdminApiService adminService;

  const _ClassStudentsSheet({
    required this.classItem,
    required this.adminService,
  });

  @override
  State<_ClassStudentsSheet> createState() => _ClassStudentsSheetState();
}

class _ClassStudentsSheetState extends State<_ClassStudentsSheet> {
  final TextEditingController _studentIdController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<ClassStudentModel> _students = [];

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  @override
  void dispose() {
    _studentIdController.dispose();
    super.dispose();
  }

  Future<void> _loadStudents() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await widget.adminService.getClassStudents(
        widget.classItem.id,
      );

      items.sort((a, b) => a.userId.compareTo(b.userId));

      if (!mounted) return;

      setState(() {
        _students = items;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _addStudent() async {
    final userId = _studentIdController.text.trim();

    if (userId.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Student ID оруулна уу')));
      return;
    }

    setState(() => _saving = true);

    try {
      await widget.adminService.addClassStudent(
        classId: widget.classItem.id,
        userId: userId,
      );

      _studentIdController.clear();

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Оюутан хичээлд нэмэгдлээ')));

      await _loadStudents();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Оюутан нэмэхэд алдаа: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _removeStudent(String userId) async {
    setState(() => _saving = true);

    try {
      await widget.adminService.removeClassStudent(
        classId: widget.classItem.id,
        userId: userId,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Оюутныг хичээлээс хаслаа')));

      await _loadStudents();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Оюутан хасахад алдаа: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Material(
      color: cs.surface,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: cs.primaryContainer,
                  child: Icon(
                    Icons.group_rounded,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${widget.classItem.name} — Students',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _studentIdController,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _saving ? null : _addStudent(),
                    decoration: InputDecoration(
                      labelText: 'Student ID',
                      hintText: 'STUDENT001',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _saving ? null : _addStudent,
                  child:
                      _saving
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 14),

            Flexible(
              child: Builder(
                builder: (context) {
                  if (_loading) {
                    return const Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (_error != null) {
                    return Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline_rounded, size: 40),
                          const SizedBox(height: 8),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: _loadStudents,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Дахин ачаалах'),
                          ),
                        ],
                      ),
                    );
                  }

                  if (_students.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text('Энэ хичээлд оюутан бүртгээгүй байна'),
                      ),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: _students.length,
                    itemBuilder: (context, index) {
                      final student = _students[index];

                      return Card(
                        elevation: 0,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: cs.secondaryContainer,
                            child: Icon(
                              Icons.person_rounded,
                              color: cs.onSecondaryContainer,
                            ),
                          ),
                          title: Text(
                            student.userId,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text('Class: ${student.classOrShiftId}'),
                          trailing: IconButton(
                            onPressed:
                                _saving
                                    ? null
                                    : () => _removeStudent(student.userId),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
