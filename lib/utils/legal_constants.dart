/// Shared legal age, terms version, and eligibility helpers for Workmate4u India.
///
/// Under Indian law (Indian Majority Act, 1875 s. 3; Indian Contract Act, 1872
/// s. 11; Child and Adolescent Labour (Prohibition and Regulation) Act, 1986;
/// Motor Vehicles Act, 1988; Digital Personal Data Protection Act, 2023 s. 2(f)
/// & s. 9), users must be at least 18 years old to enter binding contracts,
/// accept or post tasks, and consent to personal data processing.
library;

const int kMinimumLegalAge = 18;
const String kTermsVersion = '2026-11-12';
const String kLegalEffectiveDate = 'November 12, 2026';

const String kMinAgeErrorMessage =
    'You must be at least 18 years old (legal adult age in India) to use Workmate4u.';

const String kEligibilitySummaryText =
    '18+ Adults Only (India): Users below 18 years are strictly prohibited.';

/// Returns the user's completed age in whole years relative to [now].
int calculateAgeInYears(DateTime dob, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  int age = ref.year - dob.year;
  if (ref.month < dob.month || (ref.month == dob.month && ref.day < dob.day)) {
    age--;
  }
  return age;
}

/// Returns true iff [dob] is at least [kMinimumLegalAge] (18) years old.
bool isEligibleAdultDob(DateTime dob, {DateTime? now}) {
  return calculateAgeInYears(dob, now: now) >= kMinimumLegalAge;
}

/// Returns the latest selectable calendar date that still satisfies the 18+
/// requirement relative to [now]. Handles leap-day reference dates safely so a
/// 17-year-old born on March 1 cannot pass when today is Feb 29.
DateTime maxEligibleDob({DateTime? now}) {
  final ref = now ?? DateTime.now();
  final targetYear = ref.year - kMinimumLegalAge;
  final isTargetLeap =
      (targetYear % 4 == 0 && targetYear % 100 != 0) || (targetYear % 400 == 0);
  final safeDay =
      (ref.month == 2 && ref.day == 29 && !isTargetLeap) ? 28 : ref.day;
  return DateTime(targetYear, ref.month, safeDay);
}

/// Returns a safe default `initialDate` for DOB pickers, clamped to
/// `[DateTime(1920), maxEligibleDob(now: now)]`.
DateTime defaultInitialDob({DateTime? currentDob, DateTime? now}) {
  final ref = now ?? DateTime.now();
  final maxDob = maxEligibleDob(now: ref);
  if (currentDob != null) {
    if (currentDob.isAfter(maxDob)) return maxDob;
    if (currentDob.isBefore(DateTime(1920))) return DateTime(1920);
    return currentDob;
  }
  final targetYear = ref.year - 22;
  final isTargetLeap =
      (targetYear % 4 == 0 && targetYear % 100 != 0) || (targetYear % 400 == 0);
  final safeDay =
      (ref.month == 2 && ref.day == 29 && !isTargetLeap) ? 28 : ref.day;
  final suggested = DateTime(targetYear, ref.month, safeDay);
  return suggested.isAfter(maxDob) ? maxDob : suggested;
}
