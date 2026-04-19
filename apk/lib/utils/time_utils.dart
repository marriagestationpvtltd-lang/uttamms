/// Returns a human-readable "last active" string for the given [lastSeen]
/// timestamp.  Handles future dates (clock skew) gracefully by treating them
/// as "just now".
String formatLastSeen(DateTime lastSeen) {
  final diff = DateTime.now().difference(lastSeen);
  if (diff.isNegative || diff.inMinutes < 1) return 'last active just now';
  if (diff.inMinutes < 60) return 'last active ${diff.inMinutes}m ago';
  if (diff.inHours < 24) return 'last active ${diff.inHours}h ago';
  if (diff.inDays == 1) return 'last active yesterday';
  if (diff.inDays < 7) return 'last active ${diff.inDays}d ago';
  return 'last active a while ago';
}
