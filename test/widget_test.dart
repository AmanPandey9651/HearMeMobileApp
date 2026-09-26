import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:talkstrangersmobile/core/app_controller.dart';
import 'package:talkstrangersmobile/main.dart';

void main() {
  testWidgets('TalkStrangers app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppController(),
        child: const TalkStrangersApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(TalkStrangersApp), findsOneWidget);
  });
}
