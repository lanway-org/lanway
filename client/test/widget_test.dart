import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lanway_client/main.dart';

void main() {
  testWidgets('App boots to the home screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: LanwayClientApp()));
    await tester.pump();
    expect(find.text('No server yet'), findsOneWidget);
  });
}
