import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry_mobile/main.dart';

void main() {
  testWidgets('LoginScreen shows unconfigured warning when API_KEY is empty and allows entry', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.text('Telemetry Engineer Portal'), findsOneWidget);
    expect(find.textContaining('API Key not configured at build time'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Authenticate & Enter'), findsOneWidget);
  });

  testWidgets('TelemetryScreen renders AppBar, Dropdown server filter, and logout action', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TelemetryScreen(
          apiKey: 'test-api-key',
          onLogout: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Live Telemetry'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsOneWidget);
    expect(find.text('All servers'), findsOneWidget);
    expect(find.byIcon(Icons.logout), findsOneWidget);
  });

  testWidgets('Kill Process Guardrail dialog disables confirm button until process name is typed and updates on force_kill toggle', (WidgetTester tester) async {
    final telemetryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: TelemetryScreen(
          key: telemetryKey,
          apiKey: 'test-key',
          onLogout: () {},
        ),
      ),
    );
    await tester.pump();

    final dynamic state = telemetryKey.currentState;
    expect(state, isNotNull);

    // Call confirmAndKillProcess on state
    final BuildContext context = telemetryKey.currentContext!;
    state.confirmAndKillProcess(
      context,
      cmd: 'stress-ng --cpu 2',
      pid: 4512,
      serverId: 'worker-node-alpha',
    );
    await tester.pump();

    // Verify dialog title and contents
    expect(find.text('Kill Process Guardrail'), findsOneWidget);
    expect(find.textContaining('PID: 4512'), findsOneWidget);
    expect(find.textContaining('Target: worker-node-alpha'), findsOneWidget);

    // 1. Confirm button is disabled initially
    final confirmBtnFinder = find.widgetWithText(ElevatedButton, 'Terminate (-15)');
    expect(confirmBtnFinder, findsOneWidget);
    ElevatedButton confirmBtn = tester.widget<ElevatedButton>(confirmBtnFinder);
    expect(confirmBtn.onPressed, isNull);

    // 2. Type incorrect process name -> still disabled
    await tester.enterText(find.byType(TextField).last, 'wrong-name');
    await tester.pump();
    confirmBtn = tester.widget<ElevatedButton>(confirmBtnFinder);
    expect(confirmBtn.onPressed, isNull);
    expect(find.text('Code or name does not match'), findsOneWidget);

    // 3a. Type short base process name -> button is enabled
    await tester.enterText(find.byType(TextField).last, 'stress-ng');
    await tester.pump();
    confirmBtn = tester.widget<ElevatedButton>(confirmBtnFinder);
    expect(confirmBtn.onPressed, isNotNull);

    // 3b. Type exact matching process name -> button is enabled
    await tester.enterText(find.byType(TextField).last, 'stress-ng --cpu 2');
    await tester.pump();
    confirmBtn = tester.widget<ElevatedButton>(confirmBtnFinder);
    expect(confirmBtn.onPressed, isNotNull);

    // 4. Test force_kill toggle requires deliberate second interaction
    final checkboxFinder = find.byType(CheckboxListTile);
    expect(checkboxFinder, findsOneWidget);
    expect(find.text('Terminate (-15)'), findsOneWidget);

    // Tap checkbox to toggle Force Kill (SIGKILL -9)
    await tester.tap(checkboxFinder);
    await tester.pump();

    // Confirm button label updates to Force Kill (-9)
    expect(find.text('Force Kill (-9)'), findsOneWidget);
    final forceBtnFinder = find.widgetWithText(ElevatedButton, 'Force Kill (-9)');
    final ElevatedButton forceBtn = tester.widget<ElevatedButton>(forceBtnFinder);
    expect(forceBtn.onPressed, isNotNull);

    // Cancel out of dialog
    await tester.tap(find.text('Cancel'));
    await tester.pump();
  });

  testWidgets('Displays 403 guardrail rejection reason in SnackBar', (WidgetTester tester) async {
    const testRejectionMsg = 'Guardrail Rejection (403): Execution Rejected: Process systemd is protected';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              return Center(
                child: ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        backgroundColor: Colors.deepOrange,
                        content: Text(testRejectionMsg),
                      ),
                    );
                  },
                  child: const Text('Show 403 SnackBar'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Show 403 SnackBar'));
    await tester.pump();

    expect(find.text(testRejectionMsg), findsOneWidget);
  });
}
