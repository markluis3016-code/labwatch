import 'package:cloud_firestore/cloud_firestore.dart';

enum EquipmentCondition {
  good,
  needsRepair,
  damaged,
  missing,
  unknown;

  static EquipmentCondition parse(Object? value) {
    final name = value is String ? value.trim() : '';
    final normalised = name == 'needs_repair' ? 'needsRepair' : name;
    for (final condition in EquipmentCondition.values) {
      if (condition.name == normalised) return condition;
    }
    return EquipmentCondition.unknown;
  }

  String get label => switch (this) {
        EquipmentCondition.good => 'Good',
        EquipmentCondition.needsRepair => 'Needs repair',
        EquipmentCondition.damaged => 'Damaged',
        EquipmentCondition.missing => 'Missing',
        EquipmentCondition.unknown => 'Unknown',
      };

  bool get isHealthy => this == EquipmentCondition.good;
  bool get isIssue =>
      this == EquipmentCondition.damaged ||
      this == EquipmentCondition.missing;
}

/// Inventory record at `equipment/{equipmentId}`. `labId` is the owning lab.
class Equipment {
  const Equipment({
    required this.id,
    required this.name,
    required this.labId,
    this.assetId = '',
    this.quantity = 1,
    this.condition = EquipmentCondition.good,
    this.available = true,
    this.notes = '',
    this.lastInspectedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String labId;
  final String assetId;
  final int quantity;
  final EquipmentCondition condition;
  final bool available;
  final String notes;
  final DateTime? lastInspectedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isServiceable =>
      condition == EquipmentCondition.good && available && quantity > 0;

  factory Equipment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Equipment(
      id: doc.id,
      name: _string(data['name']).trim().isEmpty
          ? 'Unnamed equipment'
          : _string(data['name']),
      labId: _string(data['labId']),
      assetId: _string(data['assetId']),
      quantity: data['quantity'] is num
          ? (data['quantity'] as num).toInt().clamp(0, 100000)
          : 0,
      condition: EquipmentCondition.parse(data['condition']),
      available: data['available'] != false,
      notes: _string(data['notes']),
      lastInspectedAt: _date(data['lastInspectedAt']),
      createdAt: _date(data['createdAt']),
      updatedAt: _date(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'name': name.trim(),
        'labId': labId,
        'assetId': assetId.trim(),
        'quantity': quantity,
        'condition': condition.name,
        'available': available,
        'notes': notes.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  Equipment copyWith({
    String? name,
    String? labId,
    String? assetId,
    int? quantity,
    EquipmentCondition? condition,
    bool? available,
    String? notes,
    DateTime? lastInspectedAt,
  }) =>
      Equipment(
        id: id,
        name: name ?? this.name,
        labId: labId ?? this.labId,
        assetId: assetId ?? this.assetId,
        quantity: quantity ?? this.quantity,
        condition: condition ?? this.condition,
        available: available ?? this.available,
        notes: notes ?? this.notes,
        lastInspectedAt: lastInspectedAt ?? this.lastInspectedAt,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

/// Validation shared by the equipment form, the inspection form and tests.
class EquipmentValidator {
  static String? name(String? value) {
    final text = value?.trim() ?? '';
    if (text.length < 2) return 'Enter an equipment name.';
    if (text.length > 80) return 'Keep the name under 80 characters.';
    return null;
  }

  static String? labId(String? value) {
    if ((value ?? '').trim().isEmpty) return 'Choose a laboratory.';
    return null;
  }

  static String? quantity(String? value) {
    final parsed = int.tryParse((value ?? '').trim());
    if (parsed == null) return 'Enter a whole number.';
    if (parsed < 0 || parsed > 100000) return 'Enter a quantity from 0 to 100000.';
    return null;
  }

  static String? assetId(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    if (text.length > 60) return 'Keep the asset ID under 60 characters.';
    return null;
  }

  static String? notes(String? value) {
    if ((value ?? '').trim().length > 500) {
      return 'Keep notes under 500 characters.';
    }
    return null;
  }
}

DateTime? _date(Object? value) =>
    value is Timestamp ? value.toDate() : null;

String _string(Object? value) => value is String ? value : '';
