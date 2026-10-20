import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/messages/data/message_runs.dart';

typedef _Msg = ({String sender, DateTime at});

void main() {
  final t0 = DateTime(2026, 3, 4, 10);

  List<(bool, bool)> runs(List<_Msg> messages) => [
        for (final p in computeMessageRuns<_Msg>(
          messages,
          senderOf: (m) => m.sender,
          createdAtOf: (m) => m.at,
        ))
          (p.firstOfRun, p.lastOfRun),
      ];

  test('empty list has no runs', () {
    expect(runs(const []), isEmpty);
  });

  test('a single message is first and last of its run', () {
    expect(runs([(sender: 'a', at: t0)]), [(true, true)]);
  });

  test('consecutive messages from one sender form one run', () {
    expect(
      runs([
        (sender: 'a', at: t0),
        (sender: 'a', at: t0.add(const Duration(minutes: 1))),
        (sender: 'a', at: t0.add(const Duration(minutes: 2))),
      ]),
      [(true, false), (false, false), (false, true)],
    );
  });

  test('a change of sender breaks the run', () {
    expect(
      runs([
        (sender: 'a', at: t0),
        (sender: 'b', at: t0.add(const Duration(minutes: 1))),
        (sender: 'a', at: t0.add(const Duration(minutes: 2))),
      ]),
      [(true, true), (true, true), (true, true)],
    );
  });

  test('a gap longer than five minutes breaks the run', () {
    expect(
      runs([
        (sender: 'a', at: t0),
        (sender: 'a', at: t0.add(const Duration(minutes: 5))),
        (sender: 'a', at: t0.add(const Duration(minutes: 11))),
      ]),
      [(true, false), (false, true), (true, true)],
    );
  });

  test('a new day breaks the run even within the gap', () {
    final lateNight = DateTime(2026, 3, 4, 23, 59);
    expect(
      runs([
        (sender: 'a', at: lateNight),
        (sender: 'a', at: lateNight.add(const Duration(minutes: 2))),
      ]),
      [(true, true), (true, true)],
    );
  });
}
