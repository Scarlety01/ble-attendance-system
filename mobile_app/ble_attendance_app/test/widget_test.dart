import 'package:flutter_test/flutter_test.dart';
import 'package:ble_attendance_app/main.dart';

void main() {
  testWidgets('App builds successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const BleAttendanceApp());
    expect(find.byType(BleAttendanceApp), findsOneWidget);
  });
}
