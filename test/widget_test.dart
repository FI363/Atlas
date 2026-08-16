import 'package:flutter_test/flutter_test.dart';
import 'package:atlas/app.dart';
import 'package:atlas/widgets/top_header_bar.dart';

void main() {
  testWidgets('AtlasApp smoke test', (WidgetTester tester) async {
    // Build app and trigger a frame.
    await tester.pumpWidget(const AtlasApp());

    // Verify that TopHeaderBar renders cleanly.
    expect(find.byType(TopHeaderBar), findsOneWidget);
  });
}
