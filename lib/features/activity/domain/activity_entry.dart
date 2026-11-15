import 'package:cloud_firestore/cloud_firestore.dart';

/// One append-only entry from the `activity` collection.
class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.userId,
    required this.action,
    this.labId,
    this.details,
    this.timestamp,
  });

  final String id;
  final String userId;
  final String action;
  final String? labId;
  final String? details;
  final DateTime? timestamp;

  factory ActivityEntry.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final ts = data['timestamp'];
    return ActivityEntry(
      id: doc.id,
      userId: data['userId'] is String ? data['userId'] as String : '',
      action: data['action'] is String ? data['action'] as String : 'unknown',
      labId: data['labId'] is String ? data['labId'] as String : null,
      details: data['details'] is String ? data['details'] as String : null,
      timestamp: ts is Timestamp ? ts.toDate() : null,
    );
  }
}
