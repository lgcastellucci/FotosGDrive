enum LogLevel { info, success, error, warning }

class LogEntry {
  final DateTime timestamp;
  final String message;
  final LogLevel level;

  LogEntry({
    required this.message,
    this.level = LogLevel.info,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  String get icon {
    switch (level) {
      case LogLevel.success:
        return '✅';
      case LogLevel.error:
        return '❌';
      case LogLevel.warning:
        return '▶️';
      case LogLevel.info:
        return 'ℹ️';
    }
  }
}
