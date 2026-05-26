import 'package:flutter_test/flutter_test.dart';

import 'package:eve/main.dart';

void main() {
  testWidgets('Landing page renders Eve CTAs', (WidgetTester tester) async {
    await tester.pumpWidget(const EveApp());

    expect(find.text('EVE'), findsOneWidget);
    expect(find.text('Start Capturing'), findsOneWidget);
    expect(find.text('I Already Have an Account'), findsOneWidget);
  });
}
