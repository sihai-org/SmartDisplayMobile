class TaskVO {
  final String id;
  final String title;
  final String status;
  final String createTime;
  final String finishTime;
  final String type;

  const TaskVO({
    required this.id,
    required this.title,
    required this.status,
    required this.createTime,
    required this.finishTime,
    required this.type,
  });

  bool get isPpt => type.trim().toLowerCase() == TaskFileType.ppt;

  bool get isPdf => !isPpt;

  String get normalizedType => isPpt ? TaskFileType.ppt : TaskFileType.pdf;
}

class TaskStatus {
  static const String pending = 'pending';
  static const String running = 'running';
  static const String success = 'success';
  static const String failed = 'failed';
  static const String cancelled = 'cancelled';
}

class TaskFileType {
  static const String pdf = 'pdf';
  static const String ppt = 'ppt';
}
