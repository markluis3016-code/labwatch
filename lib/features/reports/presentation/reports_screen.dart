import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/status_colors.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/equipment.dart';
import '../../../shared/models/inspection.dart';
import '../../../shared/models/lab.dart';
import '../../../shared/models/lab_alert.dart';
import '../../../shared/models/reservation.dart';
import '../../activity/data/activity_providers.dart';
import '../../activity/domain/activity_entry.dart';
import '../../admin/data/user_admin_repository.dart';
import '../../alerts/data/alert_repository.dart';
import '../../authentication/data/auth_repository.dart';
import '../../equipment/data/equipment_repository.dart';
import '../../inspections/data/inspection_repository.dart';
import '../../labs/data/lab_repository.dart';
import '../../scheduling/data/reservation_repository.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final labs = ref.watch(labsProvider).valueOrNull ?? const <Lab>[];
    final equipment = ref.watch(equipmentProvider).valueOrNull ?? const <Equipment>[];
    final alerts = ref.watch(alertsProvider).valueOrNull ?? const <LabAlert>[];
    final reservations = ref.watch(visibleReservationsProvider);
    final inspections = (user?.isAdmin == true
            ? ref.watch(recentInspectionsProvider).valueOrNull
            : ref.watch(myInspectionsProvider).valueOrNull) ??
        const <Inspection>[];
    final activity = ref.watch(activityFeedProvider).valueOrNull ??
        const <ActivityEntry>[];
    final users = ref.watch(allUsersProvider).valueOrNull ?? const <AppUser>[];
    final labsById = ref.watch(labsByIdProvider);

    final canSeeUsers = user?.isAdmin == true;

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: PageBody(
        child: ListView(
          children: [
            const PageHeader(
              breadcrumb: 'Analysis',
              title: 'Reports and exports',
              subtitle:
                  'Reports are generated from the records currently available '
                  'in LabWatch. Energy consumption is not estimated or '
                  'invented because the system has no metered data.',
            ),
            const SizedBox(height: 16),
            const InfoBanner(
              text: 'PDF exports include only real stored records. '
                  'Historical telemetry and metered energy values are '
                  'unavailable in this build, so no consumption totals are '
                  'fabricated.',
              icon: Icons.picture_as_pdf_outlined,
            ),
            const SizedBox(height: 14),
            _ReportCard(
              title: 'Laboratory usage',
              subtitle:
                  '${labs.length} laboratories · ${reservations.length} reservation record(s) visible',
              icon: Icons.science_outlined,
              color: AppColors.royal,
              preview: _UsagePreview(
                labs: labs,
                reservations: reservations,
                labsById: labsById,
              ),
              onExport: () => _exportUsage(context, labs, reservations),
            ),
            const SizedBox(height: 12),
            _ReportCard(
              title: 'Equipment conditions',
              subtitle:
                  '${equipment.length} items · ${equipment.where((item) => item.condition.isIssue).length} issue(s)',
              icon: Icons.inventory_2_outlined,
              color: AppColors.warning,
              preview: _EquipmentPreview(equipment: equipment, labsById: labsById),
              onExport: () => _exportEquipment(context, equipment, labsById),
            ),
            const SizedBox(height: 12),
            _ReportCard(
              title: 'Equipment inspections',
              subtitle: '${inspections.length} inspection record(s) visible',
              icon: Icons.fact_check_outlined,
              color: AppColors.success,
              preview: _InspectionPreview(inspections: inspections),
              onExport: () => _exportInspections(context, inspections),
            ),
            const SizedBox(height: 12),
            _ReportCard(
              title: 'Alerts',
              subtitle:
                  '${alerts.length} alerts · ${alerts.where((alert) => !alert.status.isResolved).length} open',
              icon: Icons.warning_amber_rounded,
              color: AppColors.critical,
              preview: _AlertPreview(alerts: alerts),
              onExport: () => _exportAlerts(context, alerts, labsById),
            ),
            const SizedBox(height: 12),
            _ReportCard(
              title: 'User activity',
              subtitle: user?.isAdmin == true
                  ? '${activity.length} recent entries · all users'
                  : '${activity.length} recent entries · your account',
              icon: Icons.history,
              color: AppColors.info,
              preview: _ActivityPreview(entries: activity),
              onExport: () => _exportActivity(context, activity, user),
            ),
            if (canSeeUsers) ...[
              const SizedBox(height: 12),
              _ReportCard(
                title: 'User accounts',
                subtitle: '${users.length} registered account(s)',
                icon: Icons.manage_accounts_outlined,
                color: AppColors.royal,
                preview: _UsersPreview(users: users),
                onExport: () => _exportUsers(context, users),
              ),
            ],
            const SizedBox(height: 12),
            const SectionCard(
              title: 'Energy consumption',
              child: EmptyState(
                icon: Icons.energy_savings_leaf_outlined,
                title: 'Not available',
                message:
                    'No metered energy-consumption records are stored. '
                    'Connect power meters and record readings before '
                    'generating consumption reports.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _share(
    BuildContext context,
    String title,
    pw.Document doc,
  ) async {
    await Printing.layoutPdf(
      name: '$title.pdf',
      onLayout: (format) => doc.save(),
    );
  }

  static pw.TextStyle _h1() => pw.TextStyle(
        fontSize: 18,
        fontWeight: pw.FontWeight.bold,
      );

  static pw.Widget _header(String title, String subtitle) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('LabWatch',
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
          pw.SizedBox(height: 2),
          pw.Text(title, style: _h1()),
          pw.SizedBox(height: 2),
          pw.Text(subtitle, style: const pw.TextStyle(fontSize: 10)),
          pw.Divider(),
        ],
      );

  Future<void> _exportUsage(
    BuildContext context,
    List<Lab> labs,
    List<Reservation> reservations,
  ) async {
    final doc = pw.Document();
    final now = DateFormat.yMMMd().add_jm().format(DateTime.now());
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          _header('Laboratory usage report', 'Generated $now'),
          pw.Text('Laboratories (${labs.length})',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: const ['Name', 'Number', 'Building', 'Status', 'Capacity'],
            data: [
              for (final lab in labs)
                [
                  lab.displayName,
                  lab.number,
                  lab.building,
                  lab.status.label,
                  lab.capacity.toString(),
                ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 14),
          pw.Text('Reservations (${reservations.length})',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: const ['Lab', 'Title', 'Start', 'End', 'Status', 'Instructor'],
            data: [
              for (final r in reservations)
                [
                  r.labName,
                  r.title,
                  DateFormat.yMd().add_Hm().format(r.startAt),
                  DateFormat.yMd().add_Hm().format(r.endAt),
                  r.status.label,
                  r.instructorName,
                ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
    );
    await _share(context, 'labwatch-laboratory-usage', doc);
  }

  Future<void> _exportEquipment(
    BuildContext context,
    List<Equipment> equipment,
    Map<String, Lab> labsById,
  ) async {
    final doc = pw.Document();
    final now = DateFormat.yMMMd().add_jm().format(DateTime.now());
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          _header('Equipment condition report', 'Generated $now'),
          pw.TableHelper.fromTextArray(
            headers: const ['Name', 'Asset ID', 'Lab', 'Qty', 'Condition', 'Available'],
            data: [
              for (final item in equipment)
                [
                  item.name,
                  item.assetId,
                  labsById[item.labId]?.displayName ?? item.labId,
                  item.quantity.toString(),
                  item.condition.label,
                  item.available ? 'Yes' : 'No',
                ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    );
    await _share(context, 'labwatch-equipment', doc);
  }

  Future<void> _exportInspections(
    BuildContext context,
    List<Inspection> inspections,
  ) async {
    final doc = pw.Document();
    final now = DateFormat.yMMMd().add_jm().format(DateTime.now());
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          _header('Inspection report', 'Generated $now'),
          if (inspections.isEmpty)
            pw.Text('No inspection records available.'),
          for (final inspection in inspections) ...[
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 10),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    '${inspection.type.label} · ${inspection.labName} · '
                    '${inspection.createdAt == null ? '' : DateFormat.yMMMd().add_jm().format(inspection.createdAt!)}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    'Inspector: ${inspection.inspectorName} · '
                    '${inspection.problemCount} issue(s)',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                  if (inspection.items.isNotEmpty)
                    pw.TableHelper.fromTextArray(
                      headers: const ['Equipment', 'Condition', 'Expected', 'Found'],
                      data: [
                        for (final item in inspection.items)
                          [
                            item.name,
                            item.condition.label,
                            item.quantityExpected.toString(),
                            item.quantityFound.toString(),
                          ],
                      ],
                      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      cellStyle: const pw.TextStyle(fontSize: 8),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
    await _share(context, 'labwatch-inspections', doc);
  }

  Future<void> _exportAlerts(
    BuildContext context,
    List<LabAlert> alerts,
    Map<String, Lab> labsById,
  ) async {
    final doc = pw.Document();
    final now = DateFormat.yMMMd().add_jm().format(DateTime.now());
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          _header('Alerts report', 'Generated $now'),
          pw.TableHelper.fromTextArray(
            headers: const ['Category', 'Severity', 'Status', 'Lab', 'Title', 'Raised'],
            data: [
              for (final alert in alerts)
                [
                  alert.category.label,
                  alert.severity.label,
                  alert.status.label,
                  alert.labId.isEmpty ? '' : (labsById[alert.labId]?.displayName ?? alert.labId),
                  alert.title,
                  alert.createdAt == null ? '' : DateFormat.yMd().add_Hm().format(alert.createdAt!),
                ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
    );
    await _share(context, 'labwatch-alerts', doc);
  }

  Future<void> _exportActivity(
    BuildContext context,
    List<ActivityEntry> entries,
    AppUser? user,
  ) async {
    final doc = pw.Document();
    final now = DateFormat.yMMMd().add_jm().format(DateTime.now());
    final scope = user?.isAdmin == true ? 'All users' : 'Current user';
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          _header('Activity report', '$scope · Generated $now'),
          pw.TableHelper.fromTextArray(
            headers: const ['Time', 'Action', 'User', 'Lab', 'Details'],
            data: [
              for (final entry in entries)
                [
                  entry.timestamp == null ? '' : DateFormat.yMd().add_Hm().format(entry.timestamp!),
                  entry.action,
                  entry.userId,
                  entry.labId ?? '',
                  entry.details ?? '',
                ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
    );
    await _share(context, 'labwatch-activity', doc);
  }

  Future<void> _exportUsers(BuildContext context, List<AppUser> users) async {
    final doc = pw.Document();
    final now = DateFormat.yMMMd().add_jm().format(DateTime.now());
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          _header('User accounts report', 'Generated $now'),
          pw.TableHelper.fromTextArray(
            headers: const ['Name', 'Email', 'Role', 'Status', 'Labs'],
            data: [
              for (final user in users)
                [
                  user.displayName,
                  user.email,
                  user.role.label,
                  user.status.label,
                  user.assignedLabIds.join(', '),
                ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    );
    await _share(context, 'labwatch-users', doc);
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.preview,
    required this.onExport,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget preview;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: onExport,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Export PDF'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          preview,
        ],
      ),
    );
  }
}

class _UsagePreview extends StatelessWidget {
  const _UsagePreview({required this.labs, required this.reservations, required this.labsById});

  final List<Lab> labs;
  final List<Reservation> reservations;
  final Map<String, Lab> labsById;

  @override
  Widget build(BuildContext context) {
    final upcoming = reservations.where((r) => r.status.isUpcoming).length;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        StatusPill(label: '${labs.length} labs', color: AppColors.royal, dense: true),
        StatusPill(label: '$upcoming upcoming', color: AppColors.success, dense: true),
        StatusPill(label: '${reservations.length} total bookings', color: AppColors.info, dense: true),
      ],
    );
  }
}

class _EquipmentPreview extends StatelessWidget {
  const _EquipmentPreview({required this.equipment, required this.labsById});

  final List<Equipment> equipment;
  final Map<String, Lab> labsById;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final condition in [
          EquipmentCondition.good,
          EquipmentCondition.needsRepair,
          EquipmentCondition.damaged,
          EquipmentCondition.missing,
        ])
          if (equipment.any((item) => item.condition == condition))
            StatusPill(
              label:
                  '${condition.label}: ${equipment.where((item) => item.condition == condition).length}',
              color: condition.color,
              dense: true,
            ),
      ],
    );
  }
}

class _InspectionPreview extends StatelessWidget {
  const _InspectionPreview({required this.inspections});

  final List<Inspection> inspections;

  @override
  Widget build(BuildContext context) {
    final problems = inspections.fold<int>(0, (sum, i) => sum + i.problemCount);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        StatusPill(label: '${inspections.length} records', color: AppColors.info, dense: true),
        StatusPill(
          label: '$problems issue(s) found',
          color: problems == 0 ? AppColors.success : AppColors.critical,
          dense: true,
        ),
      ],
    );
  }
}

class _AlertPreview extends StatelessWidget {
  const _AlertPreview({required this.alerts});

  final List<LabAlert> alerts;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        StatusPill(
          label: '${alerts.where((a) => a.status.isOpen).length} open',
          color: AppColors.critical,
          dense: true,
        ),
        StatusPill(
          label: '${alerts.where((a) => a.status == AlertStatus.acknowledged).length} acknowledged',
          color: AppColors.warning,
          dense: true,
        ),
        StatusPill(
          label: '${alerts.where((a) => a.status.isResolved).length} resolved',
          color: AppColors.success,
          dense: true,
        ),
      ],
    );
  }
}

class _ActivityPreview extends StatelessWidget {
  const _ActivityPreview({required this.entries});

  final List<ActivityEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Text(
      entries.isEmpty
          ? 'No activity records available yet.'
          : 'Most recent: ${DateFormat.yMMMd().add_jm().format(entries.first.timestamp ?? DateTime.now())}',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

class _UsersPreview extends StatelessWidget {
  const _UsersPreview({required this.users});

  final List<AppUser> users;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        StatusPill(label: '${users.where((u) => u.isActive).length} active', color: AppColors.success, dense: true),
        StatusPill(label: '${users.where((u) => u.isPending).length} pending', color: AppColors.warning, dense: true),
        StatusPill(label: '${users.where((u) => u.status == AccountStatus.disabled).length} disabled', color: AppColors.critical, dense: true),
      ],
    );
  }
}
