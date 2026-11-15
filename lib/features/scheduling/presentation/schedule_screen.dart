import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/status_colors.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../../shared/errors/app_failure.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/lab.dart';
import '../../../shared/models/reservation.dart';
import '../../authentication/data/auth_repository.dart';
import '../../labs/data/lab_repository.dart';
import '../data/reservation_repository.dart';

class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({this.preselectedLabId, super.key});

  final String? preselectedLabId;

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  late DateTime _selectedDay;
  late DateTime _weekStart;
  String? _labFilter;
  bool _showAllHistory = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
    _weekStart = _startOfWeek(_selectedDay);
    _labFilter = widget.preselectedLabId;
  }

  static DateTime _startOfWeek(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    return date.subtract(Duration(days: date.weekday - 1));
  }

  static DateTime _dayOf(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  Future<void> _run(
    Future<void> Function() action, {
    required String success,
  }) async {
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
    } on AppFailure catch (failure) {
      if (!mounted) return;
      _error(failure.message);
    } catch (_) {
      if (!mounted) return;
      _error('Could not complete the request. Try again.');
    }
  }

  void _error(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final labs = ref.watch(labsProvider).valueOrNull ?? const <Lab>[];
    final reservations = ref.watch(visibleReservationsProvider);
    final labsById = ref.watch(labsByIdProvider);

    final dayReservations = reservations
        .where((reservation) {
          final sameDay = _dayOf(reservation.startAt) == _selectedDay;
          final matchesLab = _labFilter == null || reservation.labId == _labFilter;
          final visible = _showAllHistory || reservation.status.isUpcoming;
          return sameDay && matchesLab && visible;
        })
        .toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));

    final weekDays = [
      for (var i = 0; i < 7; i++) _weekStart.add(Duration(days: i)),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: () => _openReservationForm(user, labs),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Reserve'),
            ),
          ),
        ],
      ),
      body: PageBody(
        child: ListView(
          children: [
            PageHeader(
              breadcrumb: 'Scheduling',
              title: 'Laboratory calendar',
              subtitle: user?.isInstructor == true
                  ? 'Your reservations. New bookings are reviewed by staff.'
                  : 'Institution-wide reservations. Non-overlapping time slots '
                      'are enforced by a Firestore transaction.',
            ),
            const SizedBox(height: 16),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous week',
                        onPressed: () => setState(() {
                          _weekStart =
                              _weekStart.subtract(const Duration(days: 7));
                          _selectedDay =
                              _selectedDay.subtract(const Duration(days: 7));
                        }),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Text(
                          '${DateFormat.MMMd().format(_weekStart)} – '
                          '${DateFormat.MMMd().add_y().format(_weekStart.add(const Duration(days: 6)))}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next week',
                        onPressed: () => setState(() {
                          _weekStart = _weekStart.add(const Duration(days: 7));
                          _selectedDay =
                              _selectedDay.add(const Duration(days: 7));
                        }),
                        icon: const Icon(Icons.chevron_right),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          final today = _dayOf(DateTime.now());
                          _selectedDay = today;
                          _weekStart = _startOfWeek(today);
                        }),
                        child: const Text('Today'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 620;
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final day in weekDays)
                              _DayChip(
                                day: day,
                                selected: day == _selectedDay,
                                count: reservations
                                    .where((reservation) =>
                                        _dayOf(reservation.startAt) == day &&
                                        reservation.status.isUpcoming)
                                    .length,
                                onTap: () =>
                                    setState(() => _selectedDay = day),
                                compact: compact,
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 240,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Laboratory filter',
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: _labFilter,
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All laboratories'),
                            ),
                            for (final lab in labs)
                              DropdownMenuItem<String?>(
                                value: lab.id,
                                child: Text(
                                  lab.displayName,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _labFilter = value),
                        ),
                      ),
                    ),
                  ),
                  FilterChip(
                    label: const Text('Show past and cancelled'),
                    selected: _showAllHistory,
                    onSelected: (value) =>
                        setState(() => _showAllHistory = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: DateFormat.yMMMMEEEEd().format(_selectedDay),
              subtitle:
                  '${dayReservations.length} reservation(s) shown · newest first',
              child: dayReservations.isEmpty
                  ? EmptyState(
                      icon: Icons.event_available_outlined,
                      title: 'Nothing scheduled',
                      message: user?.isInstructor == true
                          ? 'Reserve a laboratory to start a booking request.'
                          : 'No reservations match this day and filter.',
                      action: FilledButton.icon(
                        onPressed: () => _openReservationForm(user, labs),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('New reservation'),
                      ),
                    )
                  : Column(
                      children: [
                        for (final reservation in dayReservations)
                          _ReservationTile(
                            reservation: reservation,
                            labName: labsById[reservation.labId]?.displayName ??
                                reservation.labName,
                            user: user,
                            onApprove: user != null && !user.isInstructor
                                ? () => _run(
                                      () => ref
                                          .read(reservationRepositoryProvider)
                                          .approve(reservation, user),
                                      success: 'Reservation approved.',
                                    )
                                : null,
                            onReject: user != null && !user.isInstructor
                                ? () => _reject(reservation, user)
                                : null,
                            onCancel: _canCancel(reservation, user)
                                ? () => _confirmCancel(reservation, user!)
                                : null,
                            onComplete: user != null &&
                                    !user.isInstructor &&
                                    reservation.status ==
                                        ReservationStatus.approved &&
                                    reservation.endAt.isBefore(DateTime.now())
                                ? () => _run(
                                      () => ref
                                          .read(reservationRepositoryProvider)
                                          .complete(reservation, user),
                                      success: 'Reservation completed.',
                                    )
                                : null,
                            onInspect: () => context.go(
                              '/inspections/new?lab=${reservation.labId}'
                              '&type=before&reservation=${reservation.id}',
                            ),
                          ),
                        const SizedBox(height: 6),
                        const InfoBanner(
                          text: 'Approved and pending bookings block the slot. '
                              'Rejected, cancelled and completed bookings release '
                              'it. Overlaps are checked again at approval time.',
                          icon: Icons.lock_clock_outlined,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  bool _canCancel(Reservation reservation, AppUser? user) {
    if (user == null) return false;
    if (reservation.status == ReservationStatus.completed ||
        reservation.status == ReservationStatus.cancelled ||
        reservation.status == ReservationStatus.rejected) {
      return false;
    }
    return reservation.instructorId == user.uid || user.isAdmin;
  }

  Future<void> _confirmCancel(Reservation reservation, AppUser user) async {
    final ok = await confirmAction(
      context,
      title: 'Cancel reservation',
      message: 'Cancel "${reservation.title}"? The slot becomes available to '
          'others.',
      confirmLabel: 'Cancel booking',
      destructive: true,
    );
    if (!ok) return;
    await _run(
      () => ref.read(reservationRepositoryProvider).cancel(reservation, user),
      success: 'Reservation cancelled.',
    );
  }

  Future<void> _reject(Reservation reservation, AppUser user) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reject reservation'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          maxLength: 200,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null) return;
    await _run(
      () => ref
          .read(reservationRepositoryProvider)
          .reject(reservation, user, reason: reason),
      success: 'Reservation rejected.',
    );
  }

  Future<void> _openReservationForm(AppUser? user, List<Lab> labs) async {
    if (user == null) return;
    if (labs.isEmpty) {
      _error('No laboratories exist yet. Ask an administrator to add one.');
      return;
    }
    final result = await showDialog<_ReservationDraft>(
      context: context,
      builder: (_) => _ReservationDialog(
        labs: labs,
        preselectedLabId: _labFilter,
        initialDay: _selectedDay,
        actor: user,
      ),
    );
    if (result == null) return;
    try {
      await ref.read(reservationRepositoryProvider).create(
            lab: result.lab,
            actor: user,
            start: result.start,
            end: result.end,
            title: result.title,
            purpose: result.purpose,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            user.isInstructor
                ? 'Reservation submitted for approval.'
                : 'Reservation created.',
          ),
        ),
      );
      setState(() {
        _selectedDay = _dayOf(result.start);
        _weekStart = _startOfWeek(_selectedDay);
      });
    } on AppFailure catch (failure) {
      if (mounted) _error(failure.message);
    } catch (_) {
      if (mounted) _error('Could not create the reservation. Try again.');
    }
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.day,
    required this.selected,
    required this.count,
    required this.onTap,
    required this.compact,
  });

  final DateTime day;
  final bool selected;
  final int count;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();
    final isToday =
        day.year == today.year && day.month == today.month && day.day == today.day;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: compact ? 62 : 78,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.secondary.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.secondary
                  : theme.colorScheme.outline,
            ),
          ),
          child: Column(
            children: [
              Text(
                DateFormat.E().format(day),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? theme.colorScheme.secondary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                day.day.toString(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: isToday ? theme.colorScheme.secondary : null,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                count == 0 ? '—' : '$count',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReservationTile extends StatelessWidget {
  const _ReservationTile({
    required this.reservation,
    required this.labName,
    required this.user,
    this.onApprove,
    this.onReject,
    this.onCancel,
    this.onComplete,
    this.onInspect,
  });

  final Reservation reservation;
  final String labName;
  final AppUser? user;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onCancel;
  final VoidCallback? onComplete;
  final VoidCallback? onInspect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: reservation.status.color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Text(
                          DateFormat.Hm().format(reservation.startAt),
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          DateFormat.Hm().format(reservation.endAt),
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reservation.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            labName,
                            reservation.instructorName,
                          ].where((part) => part.trim().isNotEmpty).join(' · '),
                          style: theme.textTheme.bodySmall,
                        ),
                        if (reservation.purpose.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            reservation.purpose,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                        if (reservation.decisionNote?.trim().isNotEmpty ==
                            true) ...[
                          const SizedBox(height: 4),
                          Text(
                            reservation.decisionNote!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(
                    label: reservation.status.label,
                    color: reservation.status.color,
                    icon: reservation.status.icon,
                    dense: true,
                  ),
                ],
              ),
              if (onApprove != null ||
                  onReject != null ||
                  onCancel != null ||
                  onComplete != null ||
                  onInspect != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    if (onApprove != null)
                      FilledButton.icon(
                        onPressed: onApprove,
                        icon: const Icon(Icons.check, size: 17),
                        label: const Text('Approve'),
                      ),
                    if (onReject != null)
                      OutlinedButton.icon(
                        onPressed: onReject,
                        icon: const Icon(Icons.close, size: 17),
                        label: const Text('Reject'),
                      ),
                    if (onCancel != null)
                      TextButton.icon(
                        onPressed: onCancel,
                        icon: const Icon(Icons.event_busy_outlined, size: 17),
                        label: const Text('Cancel'),
                      ),
                    if (onComplete != null)
                      TextButton.icon(
                        onPressed: onComplete,
                        icon: const Icon(Icons.done_all, size: 17),
                        label: const Text('Complete'),
                      ),
                    if (onInspect != null &&
                        reservation.status == ReservationStatus.approved)
                      TextButton.icon(
                        onPressed: onInspect,
                        icon: const Icon(Icons.fact_check_outlined, size: 17),
                        label: const Text('Inspect'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReservationDraft {
  const _ReservationDraft({
    required this.lab,
    required this.start,
    required this.end,
    required this.title,
    required this.purpose,
  });

  final Lab lab;
  final DateTime start;
  final DateTime end;
  final String title;
  final String purpose;
}

class _ReservationDialog extends StatefulWidget {
  const _ReservationDialog({
    required this.labs,
    required this.preselectedLabId,
    required this.initialDay,
    required this.actor,
  });

  final List<Lab> labs;
  final String? preselectedLabId;
  final DateTime initialDay;
  final AppUser actor;

  @override
  State<_ReservationDialog> createState() => _ReservationDialogState();
}

class _ReservationDialogState extends State<_ReservationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _purpose;
  late String _labId;
  late DateTime _day;
  TimeOfDay _start = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 9, minute: 0);
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController();
    _purpose = TextEditingController();
    _day = widget.initialDay;
    final available = widget.labs.where((lab) => lab.status.canBeReserved);
    final preferred = widget.preselectedLabId;
    _labId = preferred != null &&
            available.any((lab) => lab.id == preferred)
        ? preferred
        : available.isNotEmpty
            ? available.first.id
            : '';
  }

  @override
  void dispose() {
    _title.dispose();
    _purpose.dispose();
    super.dispose();
  }

  DateTime get _startAt => DateTime(
        _day.year,
        _day.month,
        _day.day,
        _start.hour,
        _start.minute,
      );

  DateTime get _endAt => DateTime(
        _day.year,
        _day.month,
        _day.day,
        _end.hour,
        _end.minute,
      );

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 180)),
    );
    if (picked != null) setState(() => _day = picked);
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : _end,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
        if (_endAt.isBefore(_startAt) || _endAt == _startAt) {
          _end = TimeOfDay(hour: (picked.hour + 1) % 24, minute: picked.minute);
        }
      } else {
        _end = picked;
      }
    });
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final lab = widget.labs.firstWhere((item) => item.id == _labId);
    final error = ReservationValidator.validateWindow(
      start: _startAt,
      end: _endAt,
      now: DateTime.now(),
    );
    final details = ReservationValidator.validateDetails(
      title: _title.text,
      purpose: _purpose.text,
      labId: _labId,
    );
    final message = error ?? details;
    if (message != null) {
      setState(() => _error = message);
      return;
    }
    Navigator.of(context).pop(
      _ReservationDraft(
        lab: lab,
        start: _startAt,
        end: _endAt,
        title: _title.text,
        purpose: _purpose.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reserveable =
        widget.labs.where((lab) => lab.status.canBeReserved).toList();
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('New reservation'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _labId.isEmpty ? null : _labId,
                  decoration: const InputDecoration(
                    labelText: 'Laboratory *',
                    prefixIcon: Icon(Icons.science_outlined),
                  ),
                  items: [
                    for (final lab in reserveable)
                      DropdownMenuItem(
                        value: lab.id,
                        child: Text(
                          [
                            lab.displayName,
                            if (lab.number.isNotEmpty) 'Lab ${lab.number}',
                          ].join(' · '),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  validator: (value) =>
                      value == null ? 'Choose a laboratory.' : null,
                  onChanged: (value) {
                    if (value != null) setState(() => _labId = value);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Title *',
                    hintText: 'e.g. Chemistry 101 laboratory',
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.length < 3) return 'Enter a short title.';
                    if (text.length > 100) return 'Keep it under 100 characters.';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final date = OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                      label: Text(DateFormat.yMMMd().format(_day)),
                    );
                    final start = OutlinedButton.icon(
                      onPressed: () => _pickTime(isStart: true),
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text('Start ${_start.format(context)}'),
                    );
                    final end = OutlinedButton.icon(
                      onPressed: () => _pickTime(isStart: false),
                      icon: const Icon(Icons.schedule_outlined, size: 18),
                      label: Text('End ${_end.format(context)}'),
                    );
                    if (constraints.maxWidth < 460) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          date,
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(child: start),
                              const SizedBox(width: 8),
                              Expanded(child: end),
                            ],
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: date),
                        const SizedBox(width: 8),
                        Expanded(child: start),
                        const SizedBox(width: 8),
                        Expanded(child: end),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _purpose,
                  maxLines: 2,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Purpose / class',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 4),
                InfoBanner(
                  text: widget.actor.isInstructor
                      ? 'Your request will be pending until staff approve it.'
                      : 'Your ${widget.actor.role.label.toLowerCase()} account '
                          'creates this booking as approved.',
                  icon: Icons.info_outline,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.actor.isInstructor ? 'Request booking' : 'Book'),
        ),
      ],
    );
  }
}
