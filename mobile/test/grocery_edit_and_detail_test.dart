import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:workmate4u/models/grocery_item.dart';
import 'package:workmate4u/models/task.dart';
import 'package:workmate4u/providers/auth_provider.dart';
import 'package:workmate4u/providers/task_provider.dart';
import 'package:workmate4u/screens/tasks/edit_task_screen.dart';
import 'package:workmate4u/theme/app_theme.dart';

void main() {
  testWidgets('EditTaskScreen grocery layout hides description/budget box and shows separate headers & item cards',
      (WidgetTester tester) async {
    final items = [
      SelectedGroceryItem(
        id: 'palak',
        name: 'Fresh Palak (Spinach)',
        category: 'Vegetables & Fruits',
        imageUrl: '',
        emoji: '🥬',
        package: '1 Bunch',
        qty: '2',
        gram: '500',
        brand: 'Local Farm',
        rupee: '40',
      ),
      SelectedGroceryItem(
        id: 'milk',
        name: 'Amul Taaza Milk',
        category: 'Dairy & Eggs',
        imageUrl: '',
        emoji: '🥛',
        package: '1L',
        qty: '1',
        litr: '1',
        brand: 'Amul',
        rupee: '56',
      ),
    ];

    final groceryTask = Task(
      id: 'task-grocery-1',
      title: 'Weekly Vegetables and Milk',
      description: GroceryCatalog.encodeGroceryItemsJson(items),
      category: 'groceries',
      budget: 97,
      status: 'open',
      posterId: 'user-1',
      posterName: 'Test Poster',
      latitude: 18.5284,
      longitude: 73.8627,
      address: 'DMart Ready / Supermarket, Main Market Road',
      dropLatitude: 18.5204,
      dropLongitude: 73.8567,
      dropAddress: 'FC Road, Shivajinagar, Pune',
      createdAt: DateTime.utc(2026, 11, 17, 10),
      groceryItems: items,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => TaskProvider()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: EditTaskScreen(task: groceryTask),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    // Bigger headers present
    expect(find.text('Task Title'), findsWidgets);
    expect(find.text('Select Category'), findsOneWidget);
    expect(find.text('Grocery Items Policy'), findsOneWidget);
    expect(find.text('Grocery Items'), findsOneWidget);
    expect(find.text('Delivery Address'), findsOneWidget);
    expect(find.text('Store Address'), findsOneWidget);
    expect(find.text('Price Breakdown'), findsOneWidget);

    // Both grocery items shown with all info
    expect(find.text('Fresh Palak (Spinach)'), findsOneWidget);
    expect(find.text('Amul Taaza Milk'), findsOneWidget);
    expect(find.text('Brand: Amul'), findsOneWidget);
    expect(find.text('Qty: 2'), findsOneWidget);
    expect(find.text('500 g'), findsOneWidget);
    expect(find.text('Est. ₹40'), findsOneWidget);

    // Description box & Budget box removed for grocery
    expect(find.text('Description'), findsNothing);
    expect(find.text('Budget (₹)'), findsNothing);

    // Updated pricing rows
    expect(find.text('Handling & Shopping Charge'), findsOneWidget);
    expect(find.text('₹30'), findsOneWidget);
    expect(find.text('Platform Fee & GST (Fixed)'), findsOneWidget);
    expect(find.text('₹12'), findsOneWidget);
    expect(groceryTask.posterFee, 12.0);
  });
}
