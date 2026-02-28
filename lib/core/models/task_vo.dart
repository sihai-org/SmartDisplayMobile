class TaskVO {
  final String id;
  final String title;
  final String status;
  final String createTime;
  final String type;

  const TaskVO({
    required this.id,
    required this.title,
    required this.status,
    required this.createTime,
    required this.type,
  });
}

class TaskStatus {
  static const String pending = 'pending';
  static const String running = 'running';
  static const String success = 'success';
  static const String failed = 'failed';
  static const String cancelled = 'cancelled';
}
