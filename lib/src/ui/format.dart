String _two(int value) => value.toString().padLeft(2, '0');

/// `14:03:22`
String clockTime(DateTime time) =>
    '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}';

/// `2026-10-11 14:03:22`
String timestamp(DateTime time) =>
    '${time.year}-${_two(time.month)}-${_two(time.day)} ${clockTime(time)}';

/// `just now`, `42s ago`, `5m ago`, `3h ago`, `2d ago`
String relativeTime(DateTime time, DateTime now) {
  final elapsed = now.difference(time);
  if (elapsed.inSeconds < 5) return 'just now';
  if (elapsed.inSeconds < 60) return '${elapsed.inSeconds}s ago';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m ago';
  if (elapsed.inHours < 24) return '${elapsed.inHours}h ago';
  return '${elapsed.inDays}d ago';
}

/// `1 port`, `2 ports`, `3 processes`
String countOf(int count, String noun, {String? plural}) =>
    '$count ${count == 1 ? noun : plural ?? '${noun}s'}';
