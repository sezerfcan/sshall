import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sshall/app/app.dart';
import 'package:sshall/theme/theme_controller.dart';

void main() {
  testWidgets('app boots and renders without crashing', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const SshallApp(),
    ));
    // After the first frame the unlock/create-vault screen is loading.
    // The MaterialApp itself must have been built successfully.
    expect(find.byType(SshallApp), findsOneWidget);
  });
}
