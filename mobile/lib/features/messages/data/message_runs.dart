/// Where a message sits in a "run" — consecutive messages from one sender, close together.
///
/// The conversation screen uses this to decide presentation only: tight spacing inside a run,
/// one avatar and one timestamp per run, a bubble tail on the last message. It never changes
/// delivery state, ordering, or which messages are shown.
class MessageRunPosition {
  final bool firstOfRun;
  final bool lastOfRun;

  const MessageRunPosition({required this.firstOfRun, required this.lastOfRun});
}

/// Messages further apart than this start a new run, even from the same sender — a reply an
/// hour later deserves its own timestamp.
const kMessageRunGap = Duration(minutes: 5);

/// Run positions for [messages] (oldest first), parallel to the input list.
///
/// A run breaks on a different sender, a new local calendar day (the list draws a date
/// separator there), or a gap longer than [kMessageRunGap].
List<MessageRunPosition> computeMessageRuns<T>(
  List<T> messages, {
  required String Function(T) senderOf,
  required DateTime Function(T) createdAtOf,
}) {
  bool continues(T previous, T next) {
    if (senderOf(previous) != senderOf(next)) return false;
    final a = createdAtOf(previous).toLocal();
    final b = createdAtOf(next).toLocal();
    if (a.year != b.year || a.month != b.month || a.day != b.day) return false;
    return b.difference(a).abs() <= kMessageRunGap;
  }

  return [
    for (var i = 0; i < messages.length; i++)
      MessageRunPosition(
        firstOfRun: i == 0 || !continues(messages[i - 1], messages[i]),
        lastOfRun: i == messages.length - 1 || !continues(messages[i], messages[i + 1]),
      ),
  ];
}
