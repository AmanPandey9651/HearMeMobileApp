import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:talkstrangersmobile/core/app_controller.dart';
import 'package:talkstrangersmobile/main.dart';
import 'package:talkstrangersmobile/widgets/feel_again_splash.dart';

void main() {
  testWidgets('FeelAgain app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppController(),
        child: const FeelAgainApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(FeelAgainApp), findsOneWidget);
    expect(find.byType(FeelAgainSplashScreen), findsOneWidget);
  });
}
