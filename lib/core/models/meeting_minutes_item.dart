class MeetingMinutesItem {
  final String id;
  final String title;
  final String date;
  final String time;
  final String markdown;
  final String taskStatus;

  const MeetingMinutesItem({
    required this.id,
    required this.title,
    required this.date,
    required this.time,
    required this.markdown,
    required this.taskStatus,
  });

  bool get isExtractedContent => taskStatus == MeetingMinutesTaskStatus.extractedContent;
}

class MeetingMinutesTaskStatus {
  static const String ongoing = 'ONGOING';
  static const String completed = 'COMPLETED';
  static const String failed = 'FAILED';
  static const String invalid = 'INVALID';
  static const String extractedContent = 'EXTRACTED_CONTENT';

  static bool isGenerating(String status) {
    return status == ongoing || status == completed;
  }

  static bool isFailed(String status) {
    return status == failed || status == invalid;
  }
}
