class DownloadItem {
  final String filename;
  final double sizeMb;
  final DateTime downloadedAt;

  DownloadItem({
    required this.filename,
    required this.sizeMb,
    required this.downloadedAt,
  });

  factory DownloadItem.fromJson(Map<String, dynamic> json) {
    return DownloadItem(
      filename: json['filename'] as String,
      sizeMb: (json['size_mb'] as num).toDouble(),
      downloadedAt: DateTime.parse(json['downloaded_at'] as String),
    );
  }
}

/// Status of the single in-flight download job the UI is tracking.
enum JobState { idle, queued, downloading, completed, failed }

class JobStatus {
  final String jobId;
  final JobState state;
  final String? filename;
  final String? error;

  JobStatus({
    required this.jobId,
    required this.state,
    this.filename,
    this.error,
  });

  factory JobStatus.fromJson(Map<String, dynamic> json) {
    return JobStatus(
      jobId: json['job_id'] as String,
      state: _parseState(json['status'] as String),
      filename: json['filename'] as String?,
      error: json['error'] as String?,
    );
  }

  static JobState _parseState(String raw) {
    switch (raw) {
      case 'queued':
        return JobState.queued;
      case 'downloading':
        return JobState.downloading;
      case 'completed':
        return JobState.completed;
      case 'failed':
        return JobState.failed;
      default:
        return JobState.idle;
    }
  }
}
