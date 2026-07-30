import 'package:flutter_test/flutter_test.dart';

import 'package:atlas/app.dart';
import 'package:atlas/widgets/top_header_bar.dart';

void main() {
  testWidgets('AtlasApp smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const AtlasApp());

    // Verify that the TopHeaderBar is rendered, indicating the shell is up.
    expect(find.byType(TopHeaderBar), findsOneWidget);
    expect(find.text('Atlas / my_flutter_project'), findsOneWidget);
  });
}
