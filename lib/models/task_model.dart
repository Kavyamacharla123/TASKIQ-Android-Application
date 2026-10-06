import 'package:cloud_firestore/cloud_firestore.dart';

class TaskModel {
  final String id;
  final String title;
  final String priority;
  final bool completed;
  final DateTime? dueTime;
  final DateTime createdAt;
  final String category;
  final String? attachmentUrl;
  final String? notes;
  final String? location;
  final double? lat;
  final double? lng;
  final double orderIndex;

  TaskModel({
    required this.id,
    required this.title,
    required this.priority,
    required this.completed,
    this.dueTime,
    required this.createdAt,
    required this.category,
    this.attachmentUrl,
    this.notes,
    this.location,
    this.lat,
    this.lng,
    required this.orderIndex,
  });

  factory TaskModel.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TaskModel(
      id: doc.id,
      title: data['title'] ?? '',
      priority: data['priority'] ?? 'Low',
      completed: data['completed'] ?? false,
      dueTime: data['dueTime'] != null ? (data['dueTime'] as Timestamp).toDate() : null,
      createdAt: data['createdAt'] != null ? (data['createdAt'] as Timestamp).toDate() : DateTime.now(),
      category: data['category'] ?? 'Personal',
      attachmentUrl: data['attachmentUrl'],
      notes: data['notes'],
      location: data['location'],
      lat: (data['lat'] as num?)?.toDouble(),
      lng: (data['lng'] as num?)?.toDouble(),
      orderIndex: (data['orderIndex'] ?? DateTime.now().millisecondsSinceEpoch.toDouble()) * 1.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'priority': priority,
      'completed': completed,
      'dueTime': dueTime != null ? Timestamp.fromDate(dueTime!) : null,
      'createdAt': Timestamp.fromDate(createdAt),
      'category': category,
      'attachmentUrl': attachmentUrl,
      'notes': notes,
      'location': location,
      'lat': lat,
      'lng': lng,
      'orderIndex': orderIndex,
    };
  }
}
