import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';

class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});

  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  // Track expanded parent category indices
  final Set<int> _expandedCategories = {};

  // Track expanded question keys: "${categoryIndex}_${questionIndex}"
  final Set<String> _expandedQuestions = {};

  void _toggleCategory(int index) {
    setState(() {
      if (_expandedCategories.contains(index)) {
        _expandedCategories.remove(index);
      } else {
        _expandedCategories.add(index);
      }
    });
  }

  void _toggleQuestion(String key) {
    setState(() {
      if (_expandedQuestions.contains(key)) {
        _expandedQuestions.remove(key);
      } else {
        _expandedQuestions.add(key);
      }
    });
  }

  Future<void> _openEmailSupport() async {
    final uri = Uri.parse(
      'mailto:info@workmate4u.com?subject=Workmate4u%20Support%20Inquiry',
    );
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open email client. Please email us at info@workmate4u.com'),
            backgroundColor: AppColors.dark,
          ),
        );
      }
    }
  }

  void _openChatSupport() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.chat_bubble_rounded, color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: 12),
            const Text(
              'Live Chat Support',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          'Our customer support executives are available 24/7. Connecting you with a live support representative...',
          style: TextStyle(color: Color(0xFF475569), fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Support ticket created. A representative will contact you in in-app chat shortly.'),
                  backgroundColor: AppColors.primary,
                ),
              );
            },
            child: const Text('Start Chat'),
          ),
        ],
      ),
    );
  }

  void _showNeedMoreHelpBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 20,
              offset: Offset(0, -5),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Handle bar
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Header title
            const Text(
              'Need More Help?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Our team is here 24/7 to help you with any issue',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 24),

            // 2 Large Action Cards (Email & Chat as shown in user wireframe)
            Row(
              children: [
                // Email Card
                Expanded(
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      _openEmailSupport();
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2FF),
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFC7D2FE)),
                            ),
                            child: const Icon(
                              Icons.mail_rounded,
                              color: Color(0xFF6366F1),
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Email',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'info@workmate4u.com',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Chat Card
                Expanded(
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      _openChatSupport();
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0F2FE),
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFBAE6FD)),
                            ),
                            child: const Icon(
                              Icons.chat_bubble_rounded,
                              color: Color(0xFF0EA5E9),
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Chat',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Live 24/7 Agent',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const categories = _allFaqCategories;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A), size: 20),
          onPressed: () => context.pop(),
        ),
        centerTitle: true,
        title: const Text(
          'Help & Support',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Banner (Help Center & Subtitle) styled with solid app theme blue/indigo color
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.help_center_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Help Center',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Frequently Asked Questions',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Find answers to your questions below. Tap on any category to view related topics.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Parent Categories List (as shown in wireframe image 2 & 3)
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, catIndex) {
                final category = categories[catIndex];
                final isParentExpanded = _expandedCategories.contains(catIndex);

                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isParentExpanded ? const Color(0xFFCBD5E1) : const Color(0xFFE2E8F0),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // ── Parent Category Header ───────────────────────
                      InkWell(
                        onTap: () => _toggleCategory(catIndex),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  category.icon,
                                  color: AppColors.primary,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  category.title,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              // Trailing chevron indicator (shown as '>' in wireframe)
                              AnimatedRotation(
                                turns: isParentExpanded ? 0.25 : 0.0,
                                duration: const Duration(milliseconds: 200),
                                child: const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Color(0xFF64748B),
                                  size: 22,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ── Child Classes (Questions) ────────────────────
                      if (isParentExpanded) ...[
                        const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: category.items.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                          itemBuilder: (context, qIndex) {
                            final item = category.items[qIndex];
                            final qKey = '${catIndex}_$qIndex';
                            final isQuestionExpanded = _expandedQuestions.contains(qKey);

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Child Question Row with '+' indicator (as shown in wireframe image 2 & 3)
                                InkWell(
                                  onTap: () => _toggleQuestion(qKey),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 13),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.question,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: isQuestionExpanded
                                                  ? FontWeight.w600
                                                  : FontWeight.w500,
                                              color: isQuestionExpanded
                                                  ? const Color(0xFF4F46E5)
                                                  : const Color(0xFF1E293B),
                                              height: 1.35,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        // Child drop-down toggle: '+' when closed, '−' when open (per wireframe)
                                        AnimatedContainer(
                                          duration: const Duration(milliseconds: 200),
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: isQuestionExpanded
                                                ? const Color(0xFFEEF2FF)
                                                : const Color(0xFFF8FAFC),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: isQuestionExpanded
                                                  ? const Color(0xFFC7D2FE)
                                                  : const Color(0xFFE2E8F0),
                                            ),
                                          ),
                                          child: Icon(
                                            isQuestionExpanded
                                                ? Icons.remove_rounded
                                                : Icons.add_rounded,
                                            color: isQuestionExpanded
                                                ? const Color(0xFF4F46E5)
                                                : const Color(0xFF64748B),
                                            size: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // Answer Content (displayed on dropdown expand per wireframe image 3)
                                if (isQuestionExpanded)
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Text(
                                      item.answer,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        height: 1.55,
                                        color: Color(0xFF334155),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // In-page "Still have questions?" card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Text(
                    'Still have questions?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'If you cannot find an answer in our FAQs, our support team is available 24/7.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF64748B),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _showNeedMoreHelpBottomSheet,
                      icon: const Icon(Icons.support_agent_rounded, size: 20),
                      label: const Text(
                        'Contact Support',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

// ── Data Models ─────────────────────────────────────────────────────────────

class _FaqCategory {
  final String title;
  final IconData icon;
  final List<_FaqItem> items;

  const _FaqCategory({
    required this.title,
    required this.icon,
    required this.items,
  });
}

class _FaqItem {
  final String question;
  final String answer;

  const _FaqItem({
    required this.question,
    required this.answer,
  });
}

// ── Complete FAQ content from Image 1 ───────────────────────────────────────

const List<_FaqCategory> _allFaqCategories = [
  _FaqCategory(
    title: 'Getting Started',
    icon: Icons.rocket_launch_rounded,
    items: [
      _FaqItem(
        question: 'How do I create an account?',
        answer:
            'Download the Workmate4U app, tap \'Sign Up\', and register using your mobile number or email. You will receive an OTP to verify your identity.',
      ),
      _FaqItem(
        question: 'Who can register on the platform?',
        answer:
            'Anyone aged 18 or older with valid government-issued ID can register as a Poster or Helper.',
      ),
      _FaqItem(
        question: 'Is KYC verification mandatory for everyone?',
        answer:
            '• For Posters: Basic verification (mobile/email OTP) is required to post tasks.\n\n• For Helpers: Full KYC verification (Aadhaar/PAN, address proof, and bank details) is mandatory before you can accept any tasks.\n\n• Additional background checks may be conducted depending on the category of work (e.g., in-home tasks, driving/transport, security).',
      ),
      _FaqItem(
        question: 'Can I be both a Poster and a Helper?',
        answer:
            'Yes. You can switch between Poster and Helper modes from your profile at any time. However, you must complete the required verification for each mode before posting tasks or accepting work.',
      ),
    ],
  ),
  _FaqCategory(
    title: 'Posting Tasks',
    icon: Icons.assignment_rounded,
    items: [
      _FaqItem(
        question: 'How do I post a task?',
        answer:
            'Tap \'Post a Task\', choose a category, enter task details (description, location, date, time), set your budget, and submit. Helpers near you will be notified.',
      ),
      _FaqItem(
        question: 'Can I cancel a task after posting?',
        answer:
            'Yes, you can cancel before a helper is assigned at no cost. If cancelled after assignment, cancellation fees may apply as per our Cancellation Policy.',
      ),
      _FaqItem(
        question: 'Can I edit a task after posting?',
        answer:
            'You can edit task details before a helper accepts it. Once accepted, please contact the helper directly to agree on any changes.',
      ),
    ],
  ),
  _FaqCategory(
    title: 'In-App Chat, Voice Calls & Safety Regulations',
    icon: Icons.security_rounded,
    items: [
      _FaqItem(
        question: 'Can I communicate with my Helper/Poster outside the app?',
        answer:
            'No. All communication must happen through the in-app chat and internet call features. Sharing phone numbers, personal emails, social media handles, or any off-platform contact details is strictly prohibited and may result in permanent account suspension.',
      ),
      _FaqItem(
        question: 'Why does Workmate4U restrict off-platform communication?',
        answer:
            'For your safety and protection. In-app communication allows us to:\n\n• Keep an unalterable record of all interactions, agreements, and disputes.\n• Verify that instructions and task terms were understood by both parties.\n• Protect your privacy — your phone number and personal details are never shared with the other party.\n• Take action in case of harassment, fraud, or violations of our Community Guidelines.',
      ),
      _FaqItem(
        question: 'Are voice calls free, and do they use my phone balance?',
        answer:
            'All voice calls are routed through the app using your internet connection (Wi-Fi or mobile data). They do not use your cellular calling minutes or show on your phone bill. However, standard data charges from your mobile carrier may apply.',
      ),
      _FaqItem(
        question: 'Is it safe to share sensitive information in the chat?',
        answer:
            'Never share sensitive information like bank account numbers, PINs, passwords, OTPs, or government ID numbers in the chat. Workmate4U will never ask for your passwords or OTPs via chat or call.',
      ),
    ],
  ),
  _FaqCategory(
    title: 'Finding & Completing Tasks',
    icon: Icons.search_rounded,
    items: [
      _FaqItem(
        question: 'How do Helpers find tasks?',
        answer:
            'Go to \'Browse Tasks\' to view available tasks near your location. Filter by category, distance, or budget. Tap \'Accept\' or submit an offer.',
      ),
      _FaqItem(
        question: 'How do I get paid?',
        answer:
            'Once the Poster marks the task as completed and approves the work, payment is released to your registered bank account or in-app wallet within 24–48 hours.',
      ),
    ],
  ),
  _FaqCategory(
    title: 'Payments & Service Charges',
    icon: Icons.account_balance_wallet_rounded,
    items: [
      _FaqItem(
        question: 'What is Workmate4U\'s Service Charge / Platform Fee?',
        answer:
            'Workmate4U charges a small service fee on each transaction to cover platform maintenance, payment gateway costs, customer support, and user verification. This fee is automatically calculated and shown transparently before you confirm a task or accept an offer. All fees are inclusive of applicable taxes (GST) in accordance with the laws of India.',
      ),
      _FaqItem(
        question: 'Are there any hidden fees or charges?',
        answer:
            'No. Workmate4U believes in 100% transparency. Every cost — including the task amount, platform fee, GST, and any payment gateway charges — is displayed clearly before you confirm.',
      ),
      _FaqItem(
        question: 'When and how will I receive my payout (Helpers)?',
        answer:
            '• Payouts are processed to your registered bank account or UPI ID after the Poster marks the task as complete and payment is received.\n\n• Standard payout processing time is 24–48 business hours. Bank holidays and weekends may cause slight delays.\n\n• You must ensure your bank account details or UPI ID are accurate and active to avoid payout delays.',
      ),
      _FaqItem(
        question: 'What happens if a task is cancelled?',
        answer:
            '• Before helper assignment: Full refund of the task amount to the Poster. Platform fees may be non-refundable depending on the stage of cancellation.\n\n• After helper assignment: If the Poster cancels, a cancellation fee may be paid to the Helper to compensate for their time and travel. If the Helper cancels, the Poster receives a full refund.',
      ),
      _FaqItem(
        question: 'What payment methods are supported?',
        answer:
            'We support UPI (Google Pay, PhonePe, Paytm, etc.), Net Banking, Credit/Debit Cards, and popular digital wallets via our secure payment gateway.',
      ),
      _FaqItem(
        question: 'Are payment transactions secure?',
        answer:
            'Yes. All payments are processed through RBI-authorized payment aggregators using 256-bit SSL encryption. We do not store your card numbers or CVV on our servers.',
      ),
      _FaqItem(
        question: 'How do refunds work?',
        answer:
            'Refunds for eligible cancellations are credited back to the original payment method within 5–7 business days. For payments made via UPI, refunds typically reflect within 24–48 hours. If your refund has not been credited after 7 business days, please contact our support team with your transaction ID and task details.',
      ),
    ],
  ),
  _FaqCategory(
    title: 'Account & Security',
    icon: Icons.shield_rounded,
    items: [
      _FaqItem(
        question: 'How do I delete my account?',
        answer:
            'Go to Profile > Settings > Account > Delete Account. Please note that account deletion is permanent and all your task history and wallet balance will be lost.',
      ),
      _FaqItem(
        question: 'How do I update my profile?',
        answer:
            'Go to Profile > Edit Profile to update your name, photo, bio, and skills. To update verified details like Aadhaar or PAN, please contact support.',
      ),
    ],
  ),
];
