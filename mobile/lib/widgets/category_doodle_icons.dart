import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Clean, solid-color vector icon for categories.
/// Designed specifically for Workmate4u with high-precision geometry and zero gradients.
class CategoryDoodleIcon extends StatelessWidget {
  final String categoryId;
  final double size;
  final Color? color;

  const CategoryDoodleIcon({
    super.key,
    required this.categoryId,
    this.size = 28,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final key = _normalize(categoryId);
    final svgString = _solidSvgs[key] ?? _solidSvgs['other'] ?? _defaultSvg;

    return SvgPicture.string(
      svgString,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }

  static String _normalize(String input) {
    final lower = input.toLowerCase().trim();
    if (lower == 'repair' || lower == 'engineering & repair' || lower == 'engineering_repair') {
      return 'repair';
    }
    return lower
        .replaceAll('&', '')
        .replaceAll('  ', ' ')
        .trim()
        .replaceAll(' ', '_');
  }

  static const String _defaultSvg = '''
<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#EEF2FF"/>
  <rect x="14" y="14" width="8" height="8" rx="2" fill="#4F46E5"/>
  <rect x="26" y="14" width="8" height="8" rx="2" fill="#1E293B"/>
  <rect x="14" y="26" width="8" height="8" rx="2" fill="#1E293B"/>
  <rect x="26" y="26" width="8" height="8" rx="2" fill="#4F46E5"/>
</svg>
''';

  static final Map<String, String> _solidSvgs = {
    'beauty': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#F8FAFC"/>
  <rect x="20" y="24" width="8" height="15" rx="2" fill="#EEF2FF" stroke="#4F46E5" stroke-width="2"/>
  <path d="M22 24L24 14C25 14 26 15 26 17V24H22Z" fill="#4F46E5"/>
  <circle cx="33" cy="18" r="2" fill="#1E293B"/>
</svg>''',
    'care_services': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="12" fill="#EEF2FF"/>
  <path d="M24 35C24 35 13 28 13 20C13 16 16.5 13 20.5 13C22.8 13 23.5 14.5 24 15C24.5 14.5 25.2 13 27.5 13C31.5 13 35 16 35 20C35 28 24 35 24 35Z" fill="#FFFFFF" stroke="#4F46E5" stroke-width="2.5" stroke-linejoin="round"/>
  <circle cx="24" cy="23" r="2" fill="#4F46E5"/>
  <circle cx="20" cy="19" r="1.5" fill="#1E293B"/>
  <circle cx="28" cy="19" r="1.5" fill="#1E293B"/>
</svg>''',
    'carpentry': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#F8FAFC"/>
  <path d="M14 30L30 14L34 18L18 34H14V30Z" fill="#EEF2FF" stroke="#4F46E5" stroke-width="2" stroke-linejoin="round"/>
  <path d="M30 14L33 11C34.5 9.5 37 11 36.5 13L34 18" stroke="#1E293B" stroke-width="2" stroke-linecap="round"/>
  <path d="M16 32L19 29M20 28L23 25" stroke="#1E293B" stroke-width="1.5"/>
</svg>''',
    'child_care': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#F8FAFC"/>
  <circle cx="24" cy="23" r="8" fill="#EEF2FF" stroke="#4F46E5" stroke-width="2"/>
  <circle cx="17" cy="16" r="3" fill="#1E293B"/>
  <circle cx="31" cy="16" r="3" fill="#1E293B"/>
  <circle cx="21" cy="22" r="1" fill="#1E293B"/>
  <circle cx="27" cy="22" r="1" fill="#1E293B"/>
  <path d="M22 26C22 27 23 28 24 28C25 28 26 27 26 26" stroke="#4F46E5" stroke-width="1.5" stroke-linecap="round"/>
</svg>''',
    'cleaning': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#F8FAFC"/>
  <path d="M19 21V16C19 14.5 20.5 13.5 22 13.5H26L27 16H23V21" stroke="#1E293B" stroke-width="2" stroke-linecap="round"/>
  <rect x="17" y="21" width="14" height="17" rx="3" fill="#EEF2FF" stroke="#4F46E5" stroke-width="2"/>
  <circle cx="34" cy="20" r="2" fill="#4F46E5"/>
  <circle cx="36" cy="27" r="1.5" fill="#6366F1"/>
</svg>''',
    'cooking': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#F8FAFC"/>
  <ellipse cx="23" cy="30" rx="12" ry="6" fill="#EEF2FF" stroke="#4F46E5" stroke-width="2"/>
  <path d="M33 30L40 34" stroke="#1E293B" stroke-width="3" stroke-linecap="round"/>
  <path d="M18 20C18 17 20 16 19 13" stroke="#6366F1" stroke-width="2" stroke-linecap="round"/>
  <path d="M24 19C24 16 26 15 25 12" stroke="#4F46E5" stroke-width="2" stroke-linecap="round"/>
</svg>''',
    'data_entry': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#F8FAFC"/>
  <rect x="14" y="13" width="20" height="24" rx="3" fill="#EEF2FF" stroke="#4F46E5" stroke-width="2"/>
  <path d="M18 19H30M18 24H30M18 29H25" stroke="#1E293B" stroke-width="2" stroke-linecap="round"/>
</svg>''',
    'delivery': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#F8FAFC"/>
  <path d="M12 28L18 16H26L22 28H12Z" fill="#EEF2FF" stroke="#4F46E5" stroke-width="2" stroke-linejoin="round"/>
  <path d="M22 28H34L37 20H25" stroke="#1E293B" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
  <circle cx="16" cy="33" r="3" fill="#4F46E5"/>
  <circle cx="32" cy="33" r="3" fill="#4F46E5"/>
  <path d="M6 20H10M4 24H8" stroke="#6366F1" stroke-width="2" stroke-linecap="round"/>
</svg>''',
    'delivery_moving': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="12" fill="#EEF2FF"/>
  <path d="M10 20H28V33H10V20Z" fill="#FFFFFF" stroke="#4F46E5" stroke-width="2.5" stroke-linejoin="round"/>
  <path d="M28 24H35L38 28V33H28V24Z" fill="#FFFFFF" stroke="#4F46E5" stroke-width="2.5" stroke-linejoin="round"/>
  <circle cx="16" cy="35" r="3.5" fill="#1E293B"/>
  <circle cx="33" cy="35" r="3.5" fill="#1E293B"/>
  <path d="M6 24H8M5 28H8" stroke="#6366F1" stroke-width="2" stroke-linecap="round"/>
</svg>''',
    'elder_care': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#F8FAFC"/>
  <path d="M24 34C24 34 14 27 14 19C14 15.5 17 13 20.5 13C22.5 13 23.5 14 24 15C24.5 14 25.5 13 27.5 13C31 13 34 15.5 34 19C34 27 24 34 24 34Z" fill="#EEF2FF" stroke="#4F46E5" stroke-width="2"/>
  <path d="M22 22C22 20 23 19 24 19C25 19 26 20 26 22V28" stroke="#1E293B" stroke-width="2" stroke-linecap="round"/>
</svg>''',
    'electrician': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#F8FAFC"/>
  <circle cx="24" cy="24" r="14" fill="#EEF2FF" stroke="#4F46E5" stroke-width="2"/>
  <path d="M25 15L18 25H25L23 33L31 23H25L25 15Z" fill="#4F46E5" stroke="#4F46E5" stroke-width="1.5" stroke-linejoin="round"/>
</svg>''',
    'errands': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#F8FAFC"/>
  <path d="M14 28L20 18C21 16 23 15 25 15H29V22L36 24C38 25 39 27 39 30V33H15C13.5 33 13 32 13 30L14 28Z" fill="#EEF2FF" stroke="#4F46E5" stroke-width="2" stroke-linejoin="round"/>
  <path d="M13 33H39" stroke="#1E293B" stroke-width="2"/>
  <path d="M7 23H11M6 27H10" stroke="#6366F1" stroke-width="2" stroke-linecap="round"/>
</svg>''',
    'event_help': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#F8FAFC"/>
  <path d="M15 35L22 17L33 28L15 35Z" fill="#EEF2FF" stroke="#4F46E5" stroke-width="2" stroke-linejoin="round"/>
  <circle cx="34" cy="15" r="2.5" fill="#4F46E5"/>
  <circle cx="38" cy="23" r="2" fill="#1E293B"/>
  <path d="M28 14L30 18" stroke="#1E293B" stroke-width="1.8" stroke-linecap="round"/>
</svg>''',
    'freelancer': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#F8FAFC"/>
  <rect x="14" y="16" width="20" height="15" rx="3" fill="#EEF2FF" stroke="#4F46E5" stroke-width="2"/>
  <path d="M10 32H38" stroke="#1E293B" stroke-width="2.5" stroke-linecap="round"/>
  <path d="M21 23H27" stroke="#4F46E5" stroke-width="2" stroke-linecap="round"/>
</svg>''',
    'gardening': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#F8FAFC"/>
  <path d="M18 26H30L28 36H20L18 26Z" fill="#EEF2FF" stroke="#4F46E5" stroke-width="2" stroke-linejoin="round"/>
  <path d="M24 26V16M24 19C24 19 19 18 18 14C22 13 24 16 24 19ZM24 16C24 16 29 15 30 11C26 10 24 13 24 16Z" stroke="#1E293B" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
</svg>''',
    'groceries': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#F8FAFC"/>
  <path d="M13 22H35L33 36H15L13 22Z" fill="#EEF2FF" stroke="#4F46E5" stroke-width="2" stroke-linejoin="round"/>
  <path d="M17 22V17C17 14.5 19 13 21 13H27C29 13 31 14.5 31 17V22" stroke="#1E293B" stroke-width="2" stroke-linecap="round"/>
  <circle cx="21" cy="28" r="2.5" fill="#4F46E5"/>
  <path d="M26 26L29 32" stroke="#1E293B" stroke-width="2" stroke-linecap="round"/>
</svg>''',
    'home_lifestyle': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="12" fill="#EEF2FF"/>
  <path d="M14 22L24 14L34 22V34C34 35 33 36 32 36H16C15 36 14 35 14 34V22Z" fill="#FFFFFF" stroke="#4F46E5" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M21 36V26H27V36" stroke="#1E293B" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M31 16V13H35V19.5" stroke="#4F46E5" stroke-width="2" stroke-linecap="round"/>
</svg>''',
    'household': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#F8FAFC"/>
  <path d="M13 22L24 14L35 22V34H13V22Z" fill="#EEF2FF" stroke="#4F46E5" stroke-width="2" stroke-linejoin="round"/>
  <rect x="21" y="26" width="6" height="8" fill="#1E293B"/>
</svg>''',
    'laundry': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#F8FAFC"/>
  <rect x="14" y="13" width="20" height="26" rx="4" fill="#EEF2FF" stroke="#4F46E5" stroke-width="2"/>
  <circle cx="24" cy="27" r="6" stroke="#1E293B" stroke-width="2"/>
  <circle cx="19" cy="18" r="1.5" fill="#4F46E5"/>
  <circle cx="24" cy="18" r="1.5" fill="#64748B"/>
</svg>''',
    'moving': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#F8FAFC"/>
  <path d="M14 20L24 13L34 20V34H14V20Z" fill="#EEF2FF" stroke="#4F46E5" stroke-width="2" stroke-linejoin="round"/>
  <path d="M24 20V34M14 27H34" stroke="#1E293B" stroke-width="1.8"/>
  <rect x="21" y="24" width="6" height="6" fill="#4F46E5"/>
</svg>''',
    'other': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="12" fill="#EEF2FF"/>
  <rect x="14" y="14" width="8" height="8" rx="2" fill="#4F46E5"/>
  <rect x="26" y="14" width="8" height="8" rx="2" fill="#1E293B"/>
  <rect x="14" y="26" width="8" height="8" rx="2" fill="#1E293B"/>
  <rect x="26" y="26" width="8" height="8" rx="2" fill="#4F46E5"/>
</svg>''',
    'painting': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#F8FAFC"/>
  <rect x="15" y="14" width="18" height="10" rx="3" fill="#EEF2FF" stroke="#4F46E5" stroke-width="2"/>
  <path d="M33 19H36V28H26V34" stroke="#1E293B" stroke-width="2.5" stroke-linecap="round"/>
  <rect x="24" y="34" width="4" height="6" rx="1" fill="#4F46E5"/>
</svg>''',
    'pet_care': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#F8FAFC"/>
  <ellipse cx="24" cy="28" rx="6" ry="5" fill="#4F46E5"/>
  <circle cx="17" cy="20" r="2.5" fill="#1E293B"/>
  <circle cx="22" cy="17" r="2.5" fill="#1E293B"/>
  <circle cx="26" cy="17" r="2.5" fill="#1E293B"/>
  <circle cx="31" cy="20" r="2.5" fill="#1E293B"/>
</svg>''',
    'photography': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#F8FAFC"/>
  <rect x="12" y="18" width="24" height="18" rx="4" fill="#EEF2FF" stroke="#4F46E5" stroke-width="2"/>
  <circle cx="24" cy="27" r="5" stroke="#1E293B" stroke-width="2"/>
  <circle cx="31" cy="22" r="1.5" fill="#4F46E5"/>
  <path d="M19 18V15H25V18" stroke="#1E293B" stroke-width="2"/>
</svg>''',
    'plumbing': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#F8FAFC"/>
  <path d="M14 26H20V19C20 16 22 14 25 14H30V19H25V26H34V31H14V26Z" fill="#EEF2FF" stroke="#4F46E5" stroke-width="2" stroke-linejoin="round"/>
  <path d="M27 33C27 33 24 35.5 24 37C24 38 25 39 26 39C27 39 28 38 28 37C28 35.5 27 33 27 33Z" fill="#1E293B"/>
</svg>''',
    'professional': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="12" fill="#EEF2FF"/>
  <rect x="12" y="18" width="24" height="18" rx="4" fill="#FFFFFF" stroke="#4F46E5" stroke-width="2.5"/>
  <path d="M19 18V15C19 13.5 20.2 12.5 21.5 12.5H26.5C27.8 12.5 29 13.5 29 15V18" stroke="#1E293B" stroke-width="2.5" stroke-linecap="round"/>
  <path d="M12 26H36" stroke="#4F46E5" stroke-width="2"/>
  <rect x="22" y="24" width="4" height="4" rx="1" fill="#1E293B"/>
</svg>''',
    'queue_standing': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#F8FAFC"/>
  <circle cx="24" cy="25" r="12" fill="#EEF2FF" stroke="#4F46E5" stroke-width="2"/>
  <path d="M24 13V9M21 9H27" stroke="#1E293B" stroke-width="2" stroke-linecap="round"/>
  <path d="M24 25L24 19M24 25L29 25" stroke="#4F46E5" stroke-width="2" stroke-linecap="round"/>
</svg>''',
    'repair': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="12" fill="#EEF2FF"/>
  <path d="M16 32L26 22M22 18L26 14C27.5 12.5 30 12.5 31.5 14L34 16.5C35.5 18 35.5 20.5 34 22L30 26L22 18Z" stroke="#4F46E5" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M14 34L18 30L32 16" stroke="#1E293B" stroke-width="2.5" stroke-linecap="round"/>
  <circle cx="15" cy="33" r="2.5" fill="#4F46E5"/>
  <path d="M30 30L36 36M33 33L36 30" stroke="#1E293B" stroke-width="2.5" stroke-linecap="round"/>
</svg>''',
    'repair_sub': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#F8FAFC"/>
  <path d="M15 33L27 21" stroke="#1E293B" stroke-width="2.5" stroke-linecap="round"/>
  <path d="M25 17L31 23L29 25L23 19L25 17Z" fill="#4F46E5"/>
  <path d="M33 33L23 23" stroke="#4F46E5" stroke-width="2.5" stroke-linecap="round"/>
  <circle cx="21" cy="21" r="3" stroke="#4F46E5" stroke-width="2"/>
</svg>''',
    'shopping': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#F8FAFC"/>
  <path d="M15 19H33L31 35H17L15 19Z" fill="#EEF2FF" stroke="#4F46E5" stroke-width="2" stroke-linejoin="round"/>
  <path d="M20 19V15C20 13 21.8 11.5 24 11.5C26.2 11.5 28 13 28 15V19" stroke="#1E293B" stroke-width="2"/>
  <path d="M21 27L24 30L28 25" stroke="#4F46E5" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
</svg>''',
    'shopping_errands': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="12" fill="#EEF2FF"/>
  <path d="M14 18H34L32 34C32 35.5 30.5 37 29 37H19C17.5 37 16 35.5 16 34L14 18Z" fill="#FFFFFF" stroke="#4F46E5" stroke-width="2.5" stroke-linejoin="round"/>
  <path d="M20 21V15C20 12.8 21.8 11 24 11C26.2 11 28 12.8 28 15V21" stroke="#1E293B" stroke-width="2.5" stroke-linecap="round"/>
  <circle cx="24" cy="27" r="2.5" fill="#4F46E5"/>
</svg>''',
    'tech_support': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#F8FAFC"/>
  <path d="M24 13C18 13 15 17 15 22C15 26 18 29 19 32H29C30 29 33 26 33 22C33 17 30 13 24 13Z" fill="#EEF2FF" stroke="#4F46E5" stroke-width="2"/>
  <rect x="20" y="33" width="8" height="3" rx="1" fill="#1E293B"/>
  <path d="M21 22L23 19H25L27 22" stroke="#4F46E5" stroke-width="1.8" stroke-linecap="round"/>
</svg>''',
    'tutoring': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#F8FAFC"/>
  <path d="M24 14L37 20L24 26L11 20L24 14Z" fill="#EEF2FF" stroke="#4F46E5" stroke-width="2" stroke-linejoin="round"/>
  <path d="M16 23V31C16 33.5 19.5 35 24 35C28.5 35 32 33.5 32 31V23" stroke="#1E293B" stroke-width="2" stroke-linecap="round"/>
  <path d="M34 22V29" stroke="#4F46E5" stroke-width="2" stroke-linecap="round"/>
</svg>''',
    'vehicle': '''<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="10" fill="#F8FAFC"/>
  <path d="M12 28L16 20C17 18 19 17 21 17H27C29 17 31 18 32 20L36 28H38V33H10V28H12Z" fill="#EEF2FF" stroke="#4F46E5" stroke-width="2" stroke-linejoin="round"/>
  <circle cx="17" cy="33" r="3" fill="#1E293B"/>
  <circle cx="31" cy="33" r="3" fill="#1E293B"/>
  <path d="M18 21H30" stroke="#1E293B" stroke-width="1.8"/>
</svg>''',
  };
}
