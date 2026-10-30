import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Renders a crisp, modern 3D doodle vector icon for every parent group and subcategory.
class CategoryDoodleIcon extends StatelessWidget {
  final String categoryId;
  final double size;
  final Color? fallbackColor;

  const CategoryDoodleIcon({
    super.key,
    required this.categoryId,
    this.size = 32,
    this.fallbackColor,
  });

  @override
  Widget build(BuildContext context) {
    final svgString = _doodleSvgs[categoryId.toLowerCase()] ??
        _doodleSvgs[_normalizeKey(categoryId)] ??
        _defaultSvg;

    return SvgPicture.string(
      svgString,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }

  static String _normalizeKey(String input) {
    return input
        .toLowerCase()
        .replaceAll('&', '')
        .replaceAll('  ', ' ')
        .trim()
        .replaceAll(' ', '_');
  }

  // ── SVGs Registry ────────────────────────────────────────────────────────
  static const String _defaultSvg = '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#6366F1" fill-opacity="0.15"/>
  <rect x="14" y="18" width="36" height="34" rx="10" fill="url(#g_def_b)" />
  <path d="M14 28H50" stroke="#FFFFFF" stroke-opacity="0.25" stroke-width="2"/>
  <rect x="28" y="18" width="8" height="34" fill="url(#g_def_r)" />
  <circle cx="32" cy="18" r="7" fill="#FDE047" />
  <path d="M30 14L34 22M34 14L30 22" stroke="#B45309" stroke-width="1.8" stroke-linecap="round"/>
  <path d="M48 14L50 18L54 20L50 22L48 26L46 22L42 20L46 18Z" fill="#FDE047"/>
  <defs>
    <linearGradient id="g_def_b" x1="14" y1="18" x2="50" y2="52" gradientUnits="userSpaceOnUse">
      <stop stop-color="#818CF8"/>
      <stop offset="1" stop-color="#4F46E5"/>
    </linearGradient>
    <linearGradient id="g_def_r" x1="28" y1="18" x2="36" y2="52" gradientUnits="userSpaceOnUse">
      <stop stop-color="#F43F5E"/>
      <stop offset="1" stop-color="#BE123C"/>
    </linearGradient>
  </defs>
</svg>
''';

  static final Map<String, String> _doodleSvgs = {
    // ═════════════════════════════════════════════════════════════════════════
    // PARENT CATEGORY GROUPS
    // ═════════════════════════════════════════════════════════════════════════

    // 1. Engineering & Repair
    'engineering_repair': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <circle cx="26" cy="38" r="14" fill="url(#g_er_cog)"/>
  <circle cx="26" cy="38" r="6" fill="#FFFFFF"/>
  <path d="M26 21V26M26 50V55M9 38H14M38 38H43M15 27L19 31M33 45L37 49M15 49L19 45M33 31L37 27" stroke="url(#g_er_cog)" stroke-width="4.5" stroke-linecap="round"/>
  <!-- 3D Wrench Over Cog -->
  <path d="M48 10C45 8 40 9 37 13L24 29C23 30 23 32 24 33L29 38C30 39 32 39 33 38L47 23C51 20 52 15 50 12L46 16L42 14L44 10H48Z" fill="url(#g_er_wrench)" filter="drop-shadow(0px 3px 4px rgba(0,0,0,0.25))"/>
  <path d="M47 13L35 27" stroke="#FFFFFF" stroke-opacity="0.4" stroke-width="1.5" stroke-linecap="round"/>
  <path d="M12 16L14 19L17 21L14 23L12 26L10 23L7 21L10 19Z" fill="#FDE047"/>
  <defs>
    <linearGradient id="g_er_cog" x1="12" y1="24" x2="40" y2="52" gradientUnits="userSpaceOnUse">
      <stop stop-color="#38BDF8"/>
      <stop offset="1" stop-color="#0284C7"/>
    </linearGradient>
    <linearGradient id="g_er_wrench" x1="24" y1="10" x2="52" y2="38" gradientUnits="userSpaceOnUse">
      <stop stop-color="#FB923C"/>
      <stop offset="1" stop-color="#EA580C"/>
    </linearGradient>
  </defs>
</svg>
''',

    // 2. Home & Lifestyle
    'home_lifestyle': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- 3D House Base -->
  <rect x="15" y="26" width="34" height="26" rx="6" fill="url(#g_hl_wall)"/>
  <!-- Chimney -->
  <rect x="38" y="14" width="7" height="12" rx="2" fill="#F43F5E"/>
  <path d="M38 12C38 10 45 10 45 12" stroke="#CBD5E1" stroke-width="2" stroke-linecap="round"/>
  <!-- Roof -->
  <path d="M10 28L29 12C31 10.5 33 10.5 35 12L54 28C55 29 54 31 52 31H12C10 31 9 29 10 28Z" fill="url(#g_hl_roof)"/>
  <path d="M14 27L32 12.5L50 27" stroke="#FFFFFF" stroke-opacity="0.4" stroke-width="2" stroke-linecap="round"/>
  <!-- Door & Window -->
  <rect x="27" y="36" width="10" height="16" rx="4" fill="#0284C7"/>
  <circle cx="34" cy="44" r="1.5" fill="#FDE047"/>
  <rect x="19" y="32" width="6" height="6" rx="2" fill="#FEF08A"/>
  <!-- Green sprout doodle -->
  <path d="M49 44C51 40 55 40 57 43C57 46 53 48 50 49C48 49 48 47 49 44Z" fill="#22C55E"/>
  <defs>
    <linearGradient id="g_hl_roof" x1="12" y1="12" x2="52" y2="30" gradientUnits="userSpaceOnUse">
      <stop stop-color="#FB7185"/>
      <stop offset="1" stop-color="#E11D48"/>
    </linearGradient>
    <linearGradient id="g_hl_wall" x1="15" y1="26" x2="49" y2="52" gradientUnits="userSpaceOnUse">
      <stop stop-color="#F8FAFC"/>
      <stop offset="1" stop-color="#E2E8F0"/>
    </linearGradient>
  </defs>
</svg>
''',

    // 3. Delivery & Moving
    'delivery_moving': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="22" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- Van Body -->
  <rect x="8" y="24" width="34" height="24" rx="5" fill="url(#g_dm_body)"/>
  <path d="M42 28L49 28C51 28 53 30 54 32L57 39C58 41 58 42 58 44V48H42V28Z" fill="url(#g_dm_front)"/>
  <!-- Window -->
  <path d="M43 31H49L53 38H43V31Z" fill="#38BDF8"/>
  <!-- Speed Lines -->
  <path d="M3 28H6M2 34H7M4 40H6" stroke="#60A5FA" stroke-width="2" stroke-linecap="round"/>
  <!-- Wheels -->
  <circle cx="19" cy="48" r="6" fill="#1E293B"/>
  <circle cx="19" cy="48" r="2.5" fill="#94A3B8"/>
  <circle cx="48" cy="48" r="6" fill="#1E293B"/>
  <circle cx="48" cy="48" r="2.5" fill="#94A3B8"/>
  <!-- Parcel on Roof -->
  <rect x="18" y="15" width="14" height="9" rx="2" fill="#F59E0B"/>
  <path d="M25 15V24M18 19.5H32" stroke="#D97706" stroke-width="1.5"/>
  <defs>
    <linearGradient id="g_dm_body" x1="8" y1="24" x2="42" y2="48" gradientUnits="userSpaceOnUse">
      <stop stop-color="#3B82F6"/>
      <stop offset="1" stop-color="#1D4ED8"/>
    </linearGradient>
    <linearGradient id="g_dm_front" x1="42" y1="28" x2="58" y2="48" gradientUnits="userSpaceOnUse">
      <stop stop-color="#60A5FA"/>
      <stop offset="1" stop-color="#2563EB"/>
    </linearGradient>
  </defs>
</svg>
''',

    // 4. Shopping & Errands
    'shopping_errands': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- Bag Body -->
  <path d="M16 22H48L45 50C45 52 43 54 40 54H24C21 54 19 52 19 50L16 22Z" fill="url(#g_se_bag)"/>
  <!-- Bag Handles -->
  <path d="M24 24V16C24 11.5 27.5 8 32 8C36.5 8 40 11.5 40 16V24" stroke="url(#g_se_handle)" stroke-width="4" stroke-linecap="round"/>
  <!-- Star Tag -->
  <rect x="36" y="28" width="12" height="14" rx="3" fill="#FDE047" transform="rotate(12 36 28)"/>
  <circle cx="42" cy="33" r="1.5" fill="#B45309"/>
  <!-- Sparkles -->
  <path d="M12 14L14 17L17 19L14 21L12 24L10 21L7 19L10 17Z" fill="#F43F5E"/>
  <defs>
    <linearGradient id="g_se_bag" x1="16" y1="22" x2="48" y2="54" gradientUnits="userSpaceOnUse">
      <stop stop-color="#A855F7"/>
      <stop offset="1" stop-color="#7E22CE"/>
    </linearGradient>
    <linearGradient id="g_se_handle" x1="24" y1="8" x2="40" y2="24" gradientUnits="userSpaceOnUse">
      <stop stop-color="#EC4899"/>
      <stop offset="1" stop-color="#BE185D"/>
    </linearGradient>
  </defs>
</svg>
''',

    // 5. Professional
    'professional': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- Briefcase body -->
  <rect x="12" y="22" width="40" height="28" rx="7" fill="url(#g_pr_case)"/>
  <path d="M12 33H52" stroke="#1E1B4B" stroke-width="2"/>
  <!-- Handle -->
  <path d="M25 22V15C25 13 27 11 29 11H35C37 11 39 13 39 15V22" stroke="#F59E0B" stroke-width="3.5" stroke-linecap="round"/>
  <!-- Gold Lock -->
  <rect x="28" y="30" width="8" height="7" rx="2" fill="#FDE047"/>
  <circle cx="32" cy="33.5" r="1" fill="#78350F"/>
  <!-- Rocket/Success Accent -->
  <path d="M47 8L53 14M53 8L47 14" stroke="#38BDF8" stroke-width="2" stroke-linecap="round"/>
  <defs>
    <linearGradient id="g_pr_case" x1="12" y1="22" x2="52" y2="50" gradientUnits="userSpaceOnUse">
      <stop stop-color="#6366F1"/>
      <stop offset="1" stop-color="#4338CA"/>
    </linearGradient>
  </defs>
</svg>
''',

    // 6. Care Services
    'care_services': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- Heart 3D -->
  <path d="M32 49C32 49 14 38 14 24C14 17.5 19 13 25 13C28.5 13 31.5 15 32 17C32.5 15 35.5 13 39 13C45 13 50 17.5 50 24C50 38 32 49 32 49Z" fill="url(#g_cs_heart)"/>
  <path d="M22 17C18 19 16 23 16 26" stroke="#FFFFFF" stroke-opacity="0.5" stroke-width="2" stroke-linecap="round"/>
  <!-- Caring Paw inside Heart -->
  <ellipse cx="32" cy="34" rx="4.5" ry="3.5" fill="#FFFFFF"/>
  <circle cx="26" cy="27" r="2" fill="#FFFFFF"/>
  <circle cx="32" cy="25" r="2" fill="#FFFFFF"/>
  <circle cx="38" cy="27" r="2" fill="#FFFFFF"/>
  <defs>
    <linearGradient id="g_cs_heart" x1="14" y1="13" x2="50" y2="49" gradientUnits="userSpaceOnUse">
      <stop stop-color="#F43F5E"/>
      <stop offset="1" stop-color="#BE123C"/>
    </linearGradient>
  </defs>
</svg>
''',

    // 7. Other
    'other': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- Isometric 3D Cube / Gift -->
  <path d="M32 10L50 20V42L32 52L14 42V20L32 10Z" fill="url(#g_ot_top)"/>
  <path d="M32 10L50 20L32 31L14 20L32 10Z" fill="url(#g_ot_top)"/>
  <path d="M14 20L32 31V52L14 42V20Z" fill="url(#g_ot_left)"/>
  <path d="M50 20L32 31V52L50 42V20Z" fill="url(#g_ot_right)"/>
  <!-- Sparkles -->
  <circle cx="22" cy="14" r="3" fill="#FDE047"/>
  <circle cx="48" cy="14" r="2" fill="#38BDF8"/>
  <defs>
    <linearGradient id="g_ot_top" x1="14" y1="10" x2="50" y2="31" gradientUnits="userSpaceOnUse">
      <stop stop-color="#FDE047"/>
      <stop offset="1" stop-color="#F59E0B"/>
    </linearGradient>
    <linearGradient id="g_ot_left" x1="14" y1="20" x2="32" y2="52" gradientUnits="userSpaceOnUse">
      <stop stop-color="#6366F1"/>
      <stop offset="1" stop-color="#4F46E5"/>
    </linearGradient>
    <linearGradient id="g_ot_right" x1="32" y1="20" x2="50" y2="52" gradientUnits="userSpaceOnUse">
      <stop stop-color="#3B82F6"/>
      <stop offset="1" stop-color="#1D4ED8"/>
    </linearGradient>
  </defs>
</svg>
''',

    // ═════════════════════════════════════════════════════════════════════════
    // SUB-CATEGORIES
    // ═════════════════════════════════════════════════════════════════════════

    // Delivery
    'delivery': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <rect x="14" y="16" width="36" height="34" rx="6" fill="url(#g_sub_del)"/>
  <path d="M14 26H50" stroke="#FFFFFF" stroke-opacity="0.3" stroke-width="2"/>
  <path d="M32 16V50" stroke="#FEF08A" stroke-width="5"/>
  <path d="M26 13L32 16L38 13" stroke="#FEF08A" stroke-width="3" stroke-linecap="round"/>
  <!-- Speed lines -->
  <path d="M6 26H11M4 32H10M7 38H11" stroke="#38BDF8" stroke-width="2.5" stroke-linecap="round"/>
  <defs>
    <linearGradient id="g_sub_del" x1="14" y1="16" x2="50" y2="50" gradientUnits="userSpaceOnUse">
      <stop stop-color="#3B82F6"/>
      <stop offset="1" stop-color="#1E40AF"/>
    </linearGradient>
  </defs>
</svg>
''',

    // Moving
    'moving': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- 3D Box with open flap -->
  <path d="M14 24L32 12L50 24V46C50 48 48 50 46 50H18C16 50 14 48 14 46V24Z" fill="url(#g_sub_mov)"/>
  <path d="M14 24L32 34L50 24" stroke="#78350F" stroke-width="2.5"/>
  <path d="M32 34V50" stroke="#78350F" stroke-width="2.5"/>
  <!-- Adhesive tape -->
  <rect x="28" y="20" width="8" height="24" fill="#FDE047" fill-opacity="0.9" rx="1"/>
  <defs>
    <linearGradient id="g_sub_mov" x1="14" y1="12" x2="50" y2="50" gradientUnits="userSpaceOnUse">
      <stop stop-color="#FBBF24"/>
      <stop offset="1" stop-color="#D97706"/>
    </linearGradient>
  </defs>
</svg>
''',

    // Groceries
    'groceries': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- Basket -->
  <path d="M14 28H50L45 50C45 52 43 53 41 53H23C21 53 19 52 19 50L14 28Z" fill="url(#g_sub_groc)"/>
  <!-- Handle -->
  <path d="M22 28V16C22 12 26 9 32 9C38 9 42 12 42 16V28" stroke="#059669" stroke-width="3.5" stroke-linecap="round"/>
  <!-- Vegetables inside -->
  <circle cx="28" cy="24" r="6" fill="#EF4444"/>
  <path d="M36 18C38 14 44 16 43 24C41 26 36 24 36 18Z" fill="#F97316"/>
  <path d="M30 19C30 15 34 16 33 21" stroke="#22C55E" stroke-width="2" stroke-linecap="round"/>
  <defs>
    <linearGradient id="g_sub_groc" x1="14" y1="28" x2="50" y2="53" gradientUnits="userSpaceOnUse">
      <stop stop-color="#34D399"/>
      <stop offset="1" stop-color="#059669"/>
    </linearGradient>
  </defs>
</svg>
''',

    // Cooking
    'cooking': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- Pan -->
  <ellipse cx="28" cy="38" rx="18" ry="10" fill="url(#g_sub_cook)"/>
  <ellipse cx="28" cy="36" rx="16" ry="8" fill="#F59E0B"/>
  <path d="M42 38L56 46" stroke="#475569" stroke-width="5" stroke-linecap="round"/>
  <!-- Steam aroma doodles -->
  <path d="M22 26C22 22 26 20 25 15" stroke="#F97316" stroke-width="2.5" stroke-linecap="round"/>
  <path d="M30 24C30 19 34 18 33 13" stroke="#FB923C" stroke-width="2.5" stroke-linecap="round"/>
  <path d="M37 26C37 22 40 21 39 16" stroke="#F97316" stroke-width="2.5" stroke-linecap="round"/>
  <defs>
    <linearGradient id="g_sub_cook" x1="10" y1="28" x2="46" y2="48" gradientUnits="userSpaceOnUse">
      <stop stop-color="#334155"/>
      <stop offset="1" stop-color="#0F172A"/>
    </linearGradient>
  </defs>
</svg>
''',

    // Cleaning
    'cleaning': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- Spray bottle -->
  <rect x="22" y="24" width="18" height="26" rx="6" fill="url(#g_sub_clean)"/>
  <path d="M26 24V17C26 15 28 14 30 14H36" stroke="#0284C7" stroke-width="3" stroke-linecap="round"/>
  <path d="M36 11H44C46 11 47 13 46 15L43 18H36V11Z" fill="#38BDF8"/>
  <path d="M28 20L23 23" stroke="#F43F5E" stroke-width="2.5" stroke-linecap="round"/>
  <!-- Sparkles & Bubbles -->
  <circle cx="48" cy="22" r="4" fill="#38BDF8" fill-opacity="0.6"/>
  <circle cx="44" cy="34" r="3" fill="#818CF8" fill-opacity="0.6"/>
  <path d="M49 10L50 12L52 13L50 14L49 16L48 14L46 13L48 12Z" fill="#FDE047"/>
  <defs>
    <linearGradient id="g_sub_clean" x1="22" y1="24" x2="40" y2="50" gradientUnits="userSpaceOnUse">
      <stop stop-color="#38BDF8"/>
      <stop offset="1" stop-color="#0284C7"/>
    </linearGradient>
  </defs>
</svg>
''',

    // Laundry
    'laundry': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- Washing Machine -->
  <rect x="16" y="14" width="32" height="38" rx="7" fill="url(#g_sub_laund)"/>
  <circle cx="32" cy="34" r="10" fill="#0284C7"/>
  <circle cx="32" cy="34" r="7" fill="#38BDF8"/>
  <circle cx="23" cy="20" r="2.5" fill="#38BDF8"/>
  <circle cx="30" cy="20" r="2" fill="#94A3B8"/>
  <circle cx="36" cy="20" r="2" fill="#94A3B8"/>
  <path d="M30 32C32 30 34 36 36 34" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round"/>
  <defs>
    <linearGradient id="g_sub_laund" x1="16" y1="14" x2="48" y2="52" gradientUnits="userSpaceOnUse">
      <stop stop-color="#F1F5F9"/>
      <stop offset="1" stop-color="#CBD5E1"/>
    </linearGradient>
  </defs>
</svg>
''',

    // Household
    'household': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <rect x="15" y="26" width="34" height="26" rx="6" fill="#F8FAFC"/>
  <path d="M10 28L30 11C31.5 10 32.5 10 34 11L54 28H10Z" fill="url(#g_sub_house)"/>
  <rect x="27" y="36" width="10" height="16" rx="3" fill="#F59E0B"/>
  <circle cx="34" cy="44" r="1.5" fill="#FFFFFF"/>
  <rect x="19" y="32" width="6" height="6" rx="2" fill="#38BDF8"/>
  <defs>
    <linearGradient id="g_sub_house" x1="10" y1="10" x2="54" y2="28" gradientUnits="userSpaceOnUse">
      <stop stop-color="#F43F5E"/>
      <stop offset="1" stop-color="#BE123C"/>
    </linearGradient>
  </defs>
</svg>
''',

    // Shopping
    'shopping': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <path d="M16 22H48L45 50C45 52 43 54 40 54H24C21 54 19 52 19 50L16 22Z" fill="url(#g_sub_shop)"/>
  <path d="M25 22V16C25 12 28 9 32 9C36 9 39 12 39 16V22" stroke="#F43F5E" stroke-width="3.5" stroke-linecap="round"/>
  <circle cx="32" cy="34" r="6" fill="#FEF08A"/>
  <path d="M30 34L32 36L35 32" stroke="#B45309" stroke-width="2" stroke-linecap="round"/>
  <defs>
    <linearGradient id="g_sub_shop" x1="16" y1="22" x2="48" y2="54" gradientUnits="userSpaceOnUse">
      <stop stop-color="#FB7185"/>
      <stop offset="1" stop-color="#E11D48"/>
    </linearGradient>
  </defs>
</svg>
''',

    // Electrician
    'electrician': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- Circular badge with 3D bolt -->
  <circle cx="32" cy="32" r="22" fill="url(#g_sub_elec)"/>
  <path d="M34 14L22 34H33L29 50L44 28H33L34 14Z" fill="#FDE047" filter="drop-shadow(0px 2px 4px rgba(0,0,0,0.3))"/>
  <path d="M34 16L24 33H33L30 46L41 29H33L34 16Z" fill="#FEF08A"/>
  <defs>
    <linearGradient id="g_sub_elec" x1="10" y1="10" x2="54" y2="54" gradientUnits="userSpaceOnUse">
      <stop stop-color="#3B82F6"/>
      <stop offset="1" stop-color="#1E3A8A"/>
    </linearGradient>
  </defs>
</svg>
''',

    // Plumbing
    'plumbing': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- Faucet / Pipe & Droplet -->
  <path d="M14 36H24V26C24 20 29 16 35 16H42V24H35C33 24 31 26 31 28V36H46V44H14V36Z" fill="url(#g_sub_plumb)"/>
  <path d="M38 46C38 46 33 50 33 53C33 55 35 57 38 57C41 57 43 55 43 53C43 50 38 46 38 46Z" fill="#38BDF8"/>
  <defs>
    <linearGradient id="g_sub_plumb" x1="14" y1="16" x2="46" y2="44" gradientUnits="userSpaceOnUse">
      <stop stop-color="#0284C7"/>
      <stop offset="1" stop-color="#075985"/>
    </linearGradient>
  </defs>
</svg>
''',

    // Carpentry
    'carpentry': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- Wood Saw -->
  <path d="M12 40L42 16L48 22L18 46H12V40Z" fill="url(#g_sub_saw)"/>
  <path d="M16 44L44 20" stroke="#FFFFFF" stroke-opacity="0.5" stroke-width="1.5"/>
  <path d="M46 14C49 11 54 13 55 16L53 23C51 25 47 24 45 21L46 14Z" fill="#EA580C"/>
  <!-- Planks -->
  <rect x="14" y="44" width="36" height="7" rx="2" fill="#D97706"/>
  <defs>
    <linearGradient id="g_sub_saw" x1="12" y1="16" x2="48" y2="46" gradientUnits="userSpaceOnUse">
      <stop stop-color="#CBD5E1"/>
      <stop offset="1" stop-color="#64748B"/>
    </linearGradient>
  </defs>
</svg>
''',

    // Painting
    'painting': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- Roller -->
  <rect x="16" y="14" width="28" height="13" rx="4" fill="url(#g_sub_paint)"/>
  <path d="M44 20H48V34H33V42" stroke="#475569" stroke-width="4" stroke-linecap="round"/>
  <!-- Handle -->
  <rect x="30" y="42" width="6" height="12" rx="2" fill="#EA580C"/>
  <path d="M22 27V32M28 27V30" stroke="#EC4899" stroke-width="2.5" stroke-linecap="round"/>
  <defs>
    <linearGradient id="g_sub_paint" x1="16" y1="14" x2="44" y2="27" gradientUnits="userSpaceOnUse">
      <stop stop-color="#F43F5E"/>
      <stop offset="1" stop-color="#BE123C"/>
    </linearGradient>
  </defs>
</svg>
''',

    // Repair
    'repair': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- Crossed hammer & wrench -->
  <path d="M16 48L40 24" stroke="#F97316" stroke-width="5" stroke-linecap="round"/>
  <path d="M37 18L47 28L43 32L33 22L37 18Z" fill="#64748B"/>
  <path d="M48 48L24 24" stroke="#0284C7" stroke-width="5" stroke-linecap="round"/>
  <circle cx="21" cy="21" r="5" stroke="#0284C7" stroke-width="3"/>
  <defs/>
</svg>
''',

    // Vehicle
    'vehicle': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="22" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- 3D Car -->
  <path d="M12 36L18 24C19 22 22 20 25 20H39C42 20 45 22 46 24L52 36H54C56 36 57 38 56 40L55 45C54 46 53 47 51 47H13C11 47 10 46 9 45L8 40C8 38 9 36 12 36Z" fill="url(#g_sub_veh)"/>
  <!-- Windows -->
  <path d="M21 24H31V34H17L21 24Z" fill="#38BDF8"/>
  <path d="M34 24H43L47 34H34V24Z" fill="#38BDF8"/>
  <!-- Wheels -->
  <circle cx="20" cy="48" r="5" fill="#1E293B"/>
  <circle cx="20" cy="48" r="2" fill="#94A3B8"/>
  <circle cx="44" cy="48" r="5" fill="#1E293B"/>
  <circle cx="44" cy="48" r="2" fill="#94A3B8"/>
  <defs>
    <linearGradient id="g_sub_veh" x1="8" y1="20" x2="56" y2="47" gradientUnits="userSpaceOnUse">
      <stop stop-color="#EF4444"/>
      <stop offset="1" stop-color="#B91C1C"/>
    </linearGradient>
  </defs>
</svg>
''',

    // Tutoring
    'tutoring': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- Cap -->
  <path d="M32 12L52 22L32 32L12 22L32 12Z" fill="url(#g_sub_tut)"/>
  <path d="M20 27V38C20 42 25 45 32 45C39 45 44 42 44 38V27" stroke="#312E81" stroke-width="3" stroke-linecap="round"/>
  <!-- Tassel -->
  <path d="M46 25V36L44 40" stroke="#FDE047" stroke-width="2.5" stroke-linecap="round"/>
  <defs>
    <linearGradient id="g_sub_tut" x1="12" y1="12" x2="52" y2="32" gradientUnits="userSpaceOnUse">
      <stop stop-color="#6366F1"/>
      <stop offset="1" stop-color="#312E81"/>
    </linearGradient>
  </defs>
</svg>
''',

    // Freelancer
    'freelancer': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- Laptop Screen -->
  <rect x="16" y="16" width="32" height="22" rx="4" fill="url(#g_sub_free)"/>
  <rect x="19" y="19" width="26" height="16" rx="2" fill="#1E293B"/>
  <path d="M24 27L28 27M24 24L34 24" stroke="#38BDF8" stroke-width="2" stroke-linecap="round"/>
  <!-- Base -->
  <path d="M10 40H54L50 44C50 45 48 46 46 46H18C16 46 14 45 14 44L10 40Z" fill="#94A3B8"/>
  <defs>
    <linearGradient id="g_sub_free" x1="16" y1="16" x2="48" y2="38" gradientUnits="userSpaceOnUse">
      <stop stop-color="#818CF8"/>
      <stop offset="1" stop-color="#4F46E5"/>
    </linearGradient>
  </defs>
</svg>
''',

    // Data Entry
    'data_entry': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <rect x="15" y="14" width="34" height="38" rx="6" fill="#FFFFFF" stroke="#CBD5E1" stroke-width="2"/>
  <rect x="20" y="20" width="24" height="5" rx="2" fill="#3B82F6"/>
  <path d="M20 31H44M20 37H38M20 43H32" stroke="#94A3B8" stroke-width="2.5" stroke-linecap="round"/>
  <circle cx="42" cy="43" r="3" fill="#10B981"/>
  <defs/>
</svg>
''',

    // Photography
    'photography': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- Camera Body -->
  <rect x="12" y="22" width="40" height="28" rx="7" fill="url(#g_sub_cam)"/>
  <rect x="22" y="16" width="12" height="6" rx="2" fill="#1E293B"/>
  <circle cx="43" cy="27" r="2.5" fill="#EF4444"/>
  <!-- Lens -->
  <circle cx="32" cy="36" r="10" fill="#0F172A"/>
  <circle cx="32" cy="36" r="7" fill="#38BDF8"/>
  <circle cx="30" cy="34" r="2" fill="#FFFFFF"/>
  <defs>
    <linearGradient id="g_sub_cam" x1="12" y1="22" x2="52" y2="50" gradientUnits="userSpaceOnUse">
      <stop stop-color="#475569"/>
      <stop offset="1" stop-color="#1E293B"/>
    </linearGradient>
  </defs>
</svg>
''',

    // Gardening
    'gardening': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- Pot -->
  <path d="M22 36H42L39 51C39 52 37 53 36 53H28C27 53 25 52 25 51L22 36Z" fill="#EA580C"/>
  <rect x="20" y="33" width="24" height="4" rx="1.5" fill="#C2410C"/>
  <!-- Plant Sprout -->
  <path d="M32 33V20" stroke="#16A34A" stroke-width="3.5" stroke-linecap="round"/>
  <path d="M32 24C32 24 24 22 23 16C28 14 32 19 32 24Z" fill="#22C55E"/>
  <path d="M32 20C32 20 40 18 41 12C36 10 32 15 32 20Z" fill="#4ADE80"/>
  <defs/>
</svg>
''',

    // Beauty
    'beauty': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- Lipstick -->
  <rect x="25" y="30" width="14" height="22" rx="3" fill="#1E293B"/>
  <rect x="27" y="24" width="10" height="6" fill="#FDE047"/>
  <path d="M27 24L32 12C34 12 37 14 37 17V24H27Z" fill="#F43F5E"/>
  <!-- Sparkles -->
  <path d="M47 16L48 18L50 19L48 20L47 22L46 20L44 19L46 18Z" fill="#FDE047"/>
  <defs/>
</svg>
''',

    // Pet Care
    'pet_care': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- Paw print 3D -->
  <ellipse cx="32" cy="38" rx="10" ry="8" fill="url(#g_sub_paw)"/>
  <ellipse cx="20" cy="24" rx="4" ry="5" fill="url(#g_sub_paw)"/>
  <ellipse cx="28" cy="20" rx="4" ry="5.5" fill="url(#g_sub_paw)"/>
  <ellipse cx="36" cy="20" rx="4" ry="5.5" fill="url(#g_sub_paw)"/>
  <ellipse cx="44" cy="24" rx="4" ry="5" fill="url(#g_sub_paw)"/>
  <defs>
    <linearGradient id="g_sub_paw" x1="16" y1="16" x2="48" y2="46" gradientUnits="userSpaceOnUse">
      <stop stop-color="#FB923C"/>
      <stop offset="1" stop-color="#EA580C"/>
    </linearGradient>
  </defs>
</svg>
''',

    // Child Care
    'child_care': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- Teddy Face -->
  <circle cx="32" cy="36" r="14" fill="url(#g_sub_child)"/>
  <circle cx="21" cy="23" r="5" fill="#D97706"/>
  <circle cx="43" cy="23" r="5" fill="#D97706"/>
  <ellipse cx="32" cy="40" rx="6" ry="4" fill="#FEF08A"/>
  <circle cx="32" cy="39" r="2" fill="#78350F"/>
  <circle cx="27" cy="34" r="1.5" fill="#78350F"/>
  <circle cx="37" cy="34" r="1.5" fill="#78350F"/>
  <defs>
    <linearGradient id="g_sub_child" x1="18" y1="20" x2="46" y2="50" gradientUnits="userSpaceOnUse">
      <stop stop-color="#FBBF24"/>
      <stop offset="1" stop-color="#D97706"/>
    </linearGradient>
  </defs>
</svg>
''',

    // Elder Care
    'elder_care': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <path d="M32 46C32 46 16 36 16 24C16 18 20 14 26 14C29.5 14 31.5 16 32 18C32.5 16 34.5 14 38 14C44 14 48 18 48 24C48 36 32 46 32 46Z" fill="url(#g_sub_eld)"/>
  <path d="M28 26C28 24 30 22 32 22C34 22 36 24 36 26V34" stroke="#FFFFFF" stroke-width="3" stroke-linecap="round"/>
  <defs>
    <linearGradient id="g_sub_eld" x1="16" y1="14" x2="48" y2="46" gradientUnits="userSpaceOnUse">
      <stop stop-color="#F43F5E"/>
      <stop offset="1" stop-color="#E11D48"/>
    </linearGradient>
  </defs>
</svg>
''',

    // Errands
    'errands': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- Fast running sneaker -->
  <path d="M14 38L22 26C24 23 27 22 30 22H36V32L46 34C50 35 52 38 52 42V46H16C14 46 13 44 13 42L14 38Z" fill="url(#g_sub_err)"/>
  <path d="M14 46H52" stroke="#FFFFFF" stroke-width="3" stroke-linecap="round"/>
  <!-- Wind / Speed -->
  <path d="M6 30H12M4 36H10" stroke="#38BDF8" stroke-width="2.5" stroke-linecap="round"/>
  <defs>
    <linearGradient id="g_sub_err" x1="14" y1="22" x2="52" y2="46" gradientUnits="userSpaceOnUse">
      <stop stop-color="#06B6D4"/>
      <stop offset="1" stop-color="#0284C7"/>
    </linearGradient>
  </defs>
</svg>
''',

    // Queue Standing
    'queue_standing': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- Stopwatch 3D -->
  <circle cx="32" cy="34" r="18" fill="url(#g_sub_queue)"/>
  <circle cx="32" cy="34" r="14" fill="#FFFFFF"/>
  <path d="M32 16V11M29 11H35" stroke="#475569" stroke-width="3" stroke-linecap="round"/>
  <path d="M32 34L32 25M32 34L38 34" stroke="#F97316" stroke-width="2.5" stroke-linecap="round"/>
  <circle cx="32" cy="34" r="2.5" fill="#EA580C"/>
  <defs>
    <linearGradient id="g_sub_queue" x1="14" y1="16" x2="50" y2="52" gradientUnits="userSpaceOnUse">
      <stop stop-color="#F59E0B"/>
      <stop offset="1" stop-color="#D97706"/>
    </linearGradient>
  </defs>
</svg>
''',

    // Event Help
    'event_help': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- Party Popper -->
  <path d="M14 48L24 24L38 38L14 48Z" fill="url(#g_sub_eve)"/>
  <path d="M24 24L38 38" stroke="#FDE047" stroke-width="3"/>
  <!-- Confetti bits -->
  <circle cx="44" cy="18" r="3" fill="#EC4899"/>
  <rect x="36" y="14" width="4" height="4" rx="1" fill="#3B82F6"/>
  <circle cx="50" cy="28" r="2.5" fill="#10B981"/>
  <path d="M42 28L46 32" stroke="#F59E0B" stroke-width="2" stroke-linecap="round"/>
  <defs>
    <linearGradient id="g_sub_eve" x1="14" y1="24" x2="38" y2="48" gradientUnits="userSpaceOnUse">
      <stop stop-color="#8B5CF6"/>
      <stop offset="1" stop-color="#6D28D9"/>
    </linearGradient>
  </defs>
</svg>
''',

    // Tech Support
    'tech_support': '''
<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="32" cy="54" rx="20" ry="4" fill="#000000" fill-opacity="0.12"/>
  <!-- Glowing Lightbulb -->
  <path d="M32 12C23 12 18 18 18 25C18 30 22 34 24 38H40C42 34 46 30 46 25C46 18 41 12 32 12Z" fill="url(#g_sub_tech)"/>
  <rect x="25" y="40" width="14" height="3" rx="1" fill="#64748B"/>
  <rect x="27" y="44" width="10" height="3" rx="1" fill="#475569"/>
  <!-- Filament -->
  <path d="M28 26L30 21L34 21L36 26" stroke="#B45309" stroke-width="2" stroke-linecap="round"/>
  <!-- Sparkles -->
  <path d="M12 18L15 20M52 18L49 20M32 7V10" stroke="#F59E0B" stroke-width="2.5" stroke-linecap="round"/>
  <defs>
    <linearGradient id="g_sub_tech" x1="18" y1="12" x2="46" y2="38" gradientUnits="userSpaceOnUse">
      <stop stop-color="#FEF08A"/>
      <stop offset="1" stop-color="#F59E0B"/>
    </linearGradient>
  </defs>
</svg>
''',
  };
}
