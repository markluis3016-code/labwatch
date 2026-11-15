import 'package:cloud_firestore/cloud_firestore.dart';

import 'equipment.dart';

enum InspectionType {
  before,
  after;

  static InspectionType parse(Object? value) =>
      value == 'after' ? InspectionType.after : InspectionType.before;

  String get label =>
      this == InspectionType.before ? 'Before use' : 'After use';
}

class InspectionItem {
  const InspectionItem({
    required this.equipmentId,
    required this.name,
    required this.condition,
    required this.quantityExpected,
    required this.quantityFound,
    this.notes = '',
  });

  final String equipmentId;
  final String name;
  final EquipmentCondition condition;
  final int quantityExpected;
  final int quantityFound;
  final String notes;

  bool get hasProblem => condition != EquipmentCondition.good;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'equipmentId': equipmentId,
        'name': name,
        'condition': condition.name,
        'quantityExpected': quantityExpected,
        'quantityFound': quantityFound,
        'notes': notes.trim(),
      };

  factory InspectionItem.fromMap(Map<String, dynamic> data) => InspectionItem(
        equipmentId: _string(data['equipmentId']),
        name: _string(data['name']),
        condition: EquipmentCondition.parse(data['condition']),
        quantityExpected: _int(data['quantityExpected']),
        quantityFound: _int(data['quantityFound']),
        notes: _string(data['notes']),
      );
}

/// Inspection stored at `inspections/{id}`.
class Inspection {
  const Inspection({
    required this.id,
    required this.labId,
    required this.labName,
    required this.type,
    required this.inspectorId,
    required this.inspectorName,
    required this.items,
    this.reservationId = '',
    this.notes = '',
    this.createdAt,
  });

  final String id;
  final String labId;
  final String labName;
  final InspectionType type;
  final String inspectorId;
  final String inspectorName;
  final List<InspectionItem> items;
  final String reservationId;
  final String notes;
  final DateTime? createdAt;

  int get problemCount => items.where((item) => item.hasProblem).length;
  int get checkedCount => items.length;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'labId': labId,
        'labName': labName,
        'type': type.name,
        'inspectorId': inspectorId,
        'inspectorName': inspectorName,
        'reservationId': reservationId,
        'notes': notes.trim(),
        'items': items.map((item) => item.toMap()).toList(growable: false),
        'createdAt': FieldValue.serverTimestamp(),
      };

  factory Inspection.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final rawItems = data['items'];
    return Inspection(
      id: doc.id,
      labId: _string(data['labId']),
      labName: _string(data['labName']),
      type: InspectionType.parse(data['type']),
      inspectorId: _string(data['inspectorId']),
      inspectorName: _string(data['inspectorName']),
      reservationId: _string(data['reservationId']),
      notes: _string(data['notes']),
      createdAt: _date(data['createdAt']),
      items: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(InspectionItem.fromMap)
              .toList(growable: false)
          : const <InspectionItem>[],
    );
  }
}

/// Compares an after-use checklist with the matching before-use checklist and
/// returns items that got worse. Pure function, unit tested.
List<InspectionItem> regressions({
  required Inspection before,
  required Inspection after,
}) {
  final beforeById = {
    for (final item in before.items) item.equipmentId: item,
  };
  final worsened = <InspectionItem>[];
  for (final item in after.items) {
    final previous = beforeById[item.equipmentId];
    if (previous == null) continue;
    if (_rank(item.condition) > _rank(previous.condition)) worsened.add(item);
    if (item.quantityFound < previous.quantityFound) worsened.add(item);
  }
  return worsened;
}

int _rank(EquipmentCondition condition) => switch (condition) {
      EquipmentCondition.good => 0,
      EquipmentCondition.needsRepair => 1,
      EquipmentCondition.unknown => 1,
      EquipmentCondition.damaged => 2,
      EquipmentCondition.missing => 3,
    };

int _int(Object? value) => value is num ? value.toInt() : 0;

DateTime? _date(Object? value) =>
    value is Timestamp ? value.toDate() : null;

String _string(Object? value) => value is String ? value : '';
