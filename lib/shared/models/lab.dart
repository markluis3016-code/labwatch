import 'package:cloud_firestore/cloud_firestore.dart';

enum LabStatus {
  available,
  occupied,
  reserved,
  maintenance,
  offline,
  unknown;

  static LabStatus parse(Object? value) {
    final name = value is String ? value.trim().toLowerCase() : '';
    for (final status in LabStatus.values) {
      if (status.name == name) return status;
    }
    return LabStatus.unknown;
  }

  String get label => switch (this) {
        LabStatus.available => 'Available',
        LabStatus.occupied => 'In use',
        LabStatus.reserved => 'Reserved',
        LabStatus.maintenance => 'Maintenance',
        LabStatus.offline => 'Offline',
        LabStatus.unknown => 'Unknown',
      };

  bool get canBeReserved =>
      this != LabStatus.maintenance && this != LabStatus.offline;
}

/// Metadata stored at `labs/{labId}`. Live occupancy and device states come
/// from `labs/{labId}/telemetry/latest`, never from this document.
class Lab {
  const Lab({
    required this.id,
    required this.name,
    this.number = '',
    this.building = '',
    this.location = '',
    this.capacity = 0,
    this.status = LabStatus.available,
    this.notes = '',
    this.assignedStaffIds = const [],
    this.gatewayOnline = false,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String number;
  final String building;
  final String location;
  final int capacity;
  final LabStatus status;
  final String notes;
  final List<String> assignedStaffIds;

  /// Set by the IoT gateway / backend only. False means device commands can
  /// be queued but cannot be executed, so the UI must show DEMO MODE.
  final bool gatewayOnline;
  final DateTime? updatedAt;

  String get displayName => name.trim().isEmpty ? id : name.trim();

  String get where =>
      [building, location].where((part) => part.trim().isNotEmpty).join(' · ');

  factory Lab.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final staff = data['assignedStaffIds'];
    return Lab(
      id: doc.id,
      name: _string(data['name']).trim().isEmpty
          ? doc.id
          : _string(data['name']),
      number: _string(data['number']),
      building: _string(data['building']),
      location: _string(data['location']),
      capacity: data['capacity'] is num
          ? (data['capacity'] as num).toInt().clamp(0, 10000)
          : 0,
      status: LabStatus.parse(data['status']),
      notes: _string(data['notes']),
      assignedStaffIds: staff is List
          ? staff.whereType<String>().toList(growable: false)
          : const <String>[],
      gatewayOnline: data['gatewayOnline'] == true,
      updatedAt: _date(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'name': name.trim(),
        'number': number.trim(),
        'building': building.trim(),
        'location': location.trim(),
        'capacity': capacity,
        'status': status.name,
        'notes': notes.trim(),
        'assignedStaffIds': assignedStaffIds,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  Lab copyWith({
    String? name,
    String? number,
    String? building,
    String? location,
    int? capacity,
    LabStatus? status,
    String? notes,
    List<String>? assignedStaffIds,
  }) =>
      Lab(
        id: id,
        name: name ?? this.name,
        number: number ?? this.number,
        building: building ?? this.building,
        location: location ?? this.location,
        capacity: capacity ?? this.capacity,
        status: status ?? this.status,
        notes: notes ?? this.notes,
        assignedStaffIds: assignedStaffIds ?? this.assignedStaffIds,
        gatewayOnline: gatewayOnline,
        updatedAt: updatedAt,
      );
}

DateTime? _date(Object? value) =>
    value is Timestamp ? value.toDate() : null;

String _string(Object? value) => value is String ? value : '';
