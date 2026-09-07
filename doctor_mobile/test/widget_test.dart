import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_console/main.dart';

void main() {
  testWidgets('App boots to the login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const DoctorConsoleApp());
    await tester.pump();
    expect(find.text('Doctor Console'), findsWidgets);
  });
}
