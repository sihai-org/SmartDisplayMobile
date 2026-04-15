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

  bool get isPpt => normalizedType == AgentTaskType.ppt;

  bool get isDeepResearch => normalizedType == AgentTaskType.deepresearch;

  bool get isPdf => !isPpt;

  String get normalizedType => AgentTaskType.normalize(type);
}

class TaskStatus {
  static const String pending = 'pending';
  static const String running = 'running';
  static const String success = 'success';
  static const String failed = 'failed';
  static const String cancelled = 'cancelled';
}

class AgentTaskType {
  static const String deepresearch = 'deepresearch';
  static const String ppt = 'ppt';

  static const List<String> supportedList = <String>[deepresearch, ppt];

  static String normalize(String? rawType) {
    final normalized = rawType?.trim().toLowerCase() ?? '';
    switch (normalized) {
      case ppt:
        return ppt;
      case deepresearch:
        return deepresearch;
      default:
        return deepresearch;
    }
  }
}

class TaskFileType {
  static const String pdf = 'pdf';
  static const String ppt = 'ppt';
}
