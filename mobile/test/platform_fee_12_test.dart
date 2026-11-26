import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmate4u/models/task.dart';
import 'package:workmate4u/providers/task_provider.dart';
import 'package:workmate4u/screens/legal/privacy_screen.dart';
import 'package:workmate4u/screens/legal/terms_screen.dart';
import 'package:workmate4u/screens/tasks/task_in_progress_screen.dart';
import 'package:workmate4u/services/storage_service.dart';
import 'package:workmate4u/widgets/confirm_payment_dialog.dart';
import 'package:workmate4u/widgets/task_price_breakdown_card.dart';

class _FakePaymentReleasedTaskProvider extends TaskProvider {
  final Task fakeTask;
  _FakePaymentReleasedTaskProvider(this.fakeTask);

  @override
  Future<Task?> getTaskDetail(String id) async => fakeTask;

  @override
  Future<void> fetchMyTasks() async {}
}

Task _makeTask({
  required String category,
  double budget = 500.0,
  double? serviceCharge,
  String status = 'posted',
}) {
  return Task(
    id: 'task_$category',
    title: 'Test $category task',
    description: 'Testing updated fee model',
    category: category,
    budget: budget,
    serviceCharge: serviceCharge,
    status: status,
    posterId: 'poster_1',
    posterName: 'Poster',
    posterPhone: '+919999999999',
    latitude: 0,
    longitude: 0,
    createdAt: DateTime(2026, 11, 26),
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
  });

  group('New Platform Fee Model (₹12 Poster / 12% Helper)', () {
    test('Task model applies ₹12 poster fee and 12% helper fee across all categories', () {
      const categories = [
        'cleaning',
        'household',
        'delivery',
        'pickup',
        'transport',
        'moving',
        'groceries',
        'repair',
        'electrician',
        'plumbing',
        'web_app_tech',
        'other',
      ];

      expect(Task.platformCommission, 0.12);
      expect(Task.posterPlatformFeeFlat, 12.0);

      for (final cat in categories) {
        final task = _makeTask(category: cat, budget: 500.0);
        expect(task.posterFee, 12.0, reason: 'posterFee for $cat');
        expect(task.totalPosterCost, 512.0, reason: 'totalPosterCost for $cat');
        expect(task.commissionRate, 0.12, reason: 'commissionRate for $cat');
        expect(task.netEarning, 440.0, reason: 'netEarning for $cat');
      }
    });

    testWidgets('TaskInProgressScreen Payment Received popup shows 12% helper fee (never 20%)',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final paidTask = _makeTask(
        category: 'cleaning',
        budget: 500.0,
        status: 'payment_released',
      );
      final provider = _FakePaymentReleasedTaskProvider(paidTask);

      await tester.pumpWidget(
        ChangeNotifierProvider<TaskProvider>.value(
          value: provider,
          child: const MaterialApp(
            home: TaskInProgressScreen(taskId: 'task_cleaning'),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('Payment Received!')), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('₹500')), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('Platform Fee (12%)')), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('− ₹60')), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('₹440')), findsOneWidget);
      expect(find.textContaining('20%'), findsNothing);
    });

    testWidgets('TaskPriceBreakdownCard shows Flat ₹12 poster fee across general, custom, repair, and grocery',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // General task
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TaskPriceBreakdownCard(
              budget: 500,
              posterFee: 12,
              totalCost: 512,
            ),
          ),
        ),
      );
      expect(find.text('Flat ₹12'), findsOneWidget);
      expect(find.text('₹12'), findsOneWidget);
      expect(find.text('₹512'), findsOneWidget);
      expect(find.textContaining('20%'), findsNothing);

      // Repair task
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TaskPriceBreakdownCard(
              budget: 199,
              posterFee: 12,
              totalCost: 211,
              isRepair: true,
            ),
          ),
        ),
      );
      expect(find.text('Flat ₹12'), findsOneWidget);
      expect(find.text('₹12'), findsOneWidget);
      expect(find.text('₹211'), findsOneWidget);
      expect(find.text('Flat ₹20'), findsNothing);
      expect(find.textContaining('20%'), findsNothing);

      // Custom items task
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TaskPriceBreakdownCard(
              budget: 800,
              posterFee: 12,
              totalCost: 812,
              customItems: [PriceBreakdownItem(label: 'Base Work', value: '₹800')],
            ),
          ),
        ),
      );
      expect(find.text('Flat ₹12'), findsOneWidget);
      expect(find.text('₹12'), findsOneWidget);
      expect(find.text('₹812'), findsOneWidget);
      expect(find.textContaining('20%'), findsNothing);
    });

    testWidgets('ConfirmPaymentDialog displays ₹12 poster platform fee without 20%',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConfirmPaymentDialog(
              budget: 500,
              posterFee: 12,
              totalCost: 512,
              currentWalletBalance: 1000,
              onConfirm: () async => true,
            ),
          ),
        ),
      );

      expect(find.text('Platform Fee & GST'), findsOneWidget);
      expect(find.text('₹12'), findsOneWidget);
      expect(find.text('₹512'), findsOneWidget);
      expect(find.textContaining('20%'), findsNothing);
    });

    testWidgets('TermsScreen & PrivacyScreen reflect ₹12 poster fee and 12% helper fee without 20%',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: TermsScreen()));
      expect(find.textContaining('Flat ₹12'), findsWidgets);
      expect(find.textContaining('12%'), findsWidgets);
      expect(find.textContaining('20%'), findsNothing);

      await tester.pumpWidget(const MaterialApp(home: PrivacyScreen()));
      expect(find.textContaining('₹12 poster fee & 12% helper fee'), findsWidgets);
      expect(find.textContaining('20%'), findsNothing);
    });
  });
}
