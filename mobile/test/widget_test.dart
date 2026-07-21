import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lc_connect/main.dart';

void main() {
  testWidgets('App launches without crash', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: LcConnectApp()));
    await tester.pump();
    // App rendered without throwing
  });
}
