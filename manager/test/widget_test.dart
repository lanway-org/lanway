import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lanway_manager/main.dart';

void main() {
  testWidgets('App boots to the connect screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: LanwayManagerApp()));
    await tester.pump();
    expect(find.text('Run a server, share freedom.'), findsOneWidget);
  });
}
