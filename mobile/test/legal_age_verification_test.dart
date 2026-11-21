import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmate4u/models/user.dart';
import 'package:workmate4u/providers/auth_provider.dart';
import 'package:workmate4u/screens/auth/google_profile_popup.dart' as alt_popup;
import 'package:workmate4u/screens/auth/login_screen.dart';
import 'package:workmate4u/screens/auth/register_screen.dart';
import 'package:workmate4u/screens/legal/privacy_screen.dart';
import 'package:workmate4u/screens/legal/terms_screen.dart';
import 'package:workmate4u/screens/profile/kyc_screen.dart';
import 'package:workmate4u/screens/profile/physical_onboarding_screen.dart';
import 'package:workmate4u/screens/tutorial/tutorial_screen.dart';
import 'package:workmate4u/services/storage_service.dart';
import 'package:workmate4u/utils/legal_constants.dart';
import 'package:workmate4u/widgets/google_profile_popup.dart';

void main() {
  group('Indian 18+ Legal Age Helpers', () {
    test('rejects underage DOBs including one day before 18th birthday', () {
      final ref = DateTime(2026, 11, 12);
      // 17 years old (birthday tomorrow)
      final almost18 = DateTime(2008, 11, 13);
      expect(calculateAgeInYears(almost18, now: ref), 17);
      expect(isEligibleAdultDob(almost18, now: ref), isFalse);

      // Exact 18th birthday today
      final exact18 = DateTime(2008, 11, 12);
      expect(calculateAgeInYears(exact18, now: ref), 18);
      expect(isEligibleAdultDob(exact18, now: ref), isTrue);

      // 16 years old (previously allowed)
      final sixteen = DateTime(2010, 1, 1);
      expect(calculateAgeInYears(sixteen, now: ref), 16);
      expect(isEligibleAdultDob(sixteen, now: ref), isFalse);
    });

    test('maxEligibleDob handles leap day safely', () {
      final leapRef = DateTime(2028, 2, 29);
      final maxDob = maxEligibleDob(now: leapRef);
      expect(maxDob, DateTime(2010, 2, 28));
      expect(isEligibleAdultDob(maxDob, now: leapRef), isTrue);
      // March 1, 2010 is still 17 on Feb 29, 2028
      expect(isEligibleAdultDob(DateTime(2010, 3, 1), now: leapRef), isFalse);
    });

    test('User.isConfirmedUnderage detects underage DOB in JSON', () {
      final underage = User.fromJson({
        'id': 'u1',
        'name': 'Test Teen',
        'email': 'teen@example.com',
        'dob': '2010-05-01',
      });
      expect(underage.isConfirmedUnderage, isTrue);

      final adult = User.fromJson({
        'id': 'u2',
        'name': 'Test Adult',
        'email': 'adult@example.com',
        'dob': '1998-05-01',
      });
      expect(adult.isConfirmedUnderage, isFalse);
    });
  });

  group('Legal & Onboarding Screens Compliance', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await StorageService.init();
    });

    testWidgets('TermsScreen enforces 18+, Child Labour compliance & actual app rules',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: TermsScreen()));

      expect(find.textContaining('18+'), findsWidgets);
      expect(find.textContaining('Child and Adolescent Labour'), findsWidgets);
      expect(find.textContaining('November 12, 2026'), findsWidgets);
      expect(find.textContaining('Verify & Pay Now'), findsWidgets);
      expect(find.textContaining('20%'), findsWidgets);
      expect(find.textContaining('Indian Majority Act, 1875'), findsWidgets);
      expect(find.textContaining('Section 79'), findsWidgets);

      // Must NOT contain stale 16+ or May 22, 2026 terms
      expect(find.textContaining('16 years'), findsNothing);
      expect(find.textContaining('below 16'), findsNothing);
      expect(find.textContaining('May 22, 2026'), findsNothing);
    });

    testWidgets('PrivacyScreen enforces DPDPA 2023 s. 9 (under 18) & full data inventory',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: PrivacyScreen()));

      expect(find.textContaining('DPDP Act, 2023'), findsWidgets);
      expect(find.textContaining('18+'), findsWidgets);
      expect(find.textContaining('Aadhaar'), findsWidgets);
      expect(find.textContaining('IFSC'), findsWidgets);
      expect(find.textContaining('November 12, 2026'), findsWidgets);

      expect(find.textContaining('under 16'), findsNothing);
      expect(find.textContaining('16+ age'), findsNothing);
      expect(find.textContaining('May 22, 2026'), findsNothing);
    });

    testWidgets('LoginScreen & RegisterScreen display 18+ eligibility & policy links',
        (tester) async {
      final auth = AuthProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: const MaterialApp(home: LoginScreen()),
        ),
      );
      expect(find.textContaining('18+ Adults Only'), findsOneWidget);
      expect(find.text('Terms & Conditions'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: const MaterialApp(home: RegisterScreen()),
        ),
      );
      expect(find.textContaining('18+ Adults Only'), findsOneWidget);

      // Expand email form to verify 18+ DOB label and checkboxes
      await tester.tap(find.text('Register with email instead'));
      await tester.pumpAndSettle();
      expect(find.text('Date of birth (18+)'), findsOneWidget);
      expect(
        find.text('I confirm I am 18+ years old and agree to the '),
        findsOneWidget,
      );
    });

    testWidgets('GoogleProfilePopup enforces 18+ and duplicate popup removes Skip bypass',
        (tester) async {
      final auth = AuthProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: const MaterialApp(home: Scaffold(body: GoogleProfilePopup())),
        ),
      );
      expect(find.textContaining('18+'), findsWidgets);
      expect(find.text('Date of Birth (Must be 18+)'), findsOneWidget);
      expect(find.text('Skip for now'), findsNothing);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: const MaterialApp(
            home: Scaffold(body: alt_popup.GoogleProfilePopup()),
          ),
        ),
      );
      expect(find.textContaining('18+'), findsWidgets);
      expect(find.text('Date of Birth (Must be 18+)'), findsOneWidget);
      expect(find.text('Skip for now'), findsNothing);
    });

    testWidgets('Tutorial, KYC, and Physical Onboarding confirm 18+ adult requirement',
        (tester) async {
      final auth = AuthProvider();

      await tester.pumpWidget(const MaterialApp(home: TutorialScreen()));
      expect(find.textContaining('18 years old'), findsOneWidget);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: const MaterialApp(home: KycScreen()),
        ),
      );
      expect(find.textContaining('at least 18 years old'), findsOneWidget);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: const MaterialApp(home: PhysicalOnboardingScreen()),
        ),
      );
      expect(find.textContaining('at least 18 years old'), findsOneWidget);
    });
  });
}
