import 'package:flutter/material.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF6366F1),
        foregroundColor: Colors.white,
        title: const Text('Terms of Service',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(
              'Terms of Service',
              'Please read these terms carefully before using Workmate4u.',
              'Effective Date: May 22, 2026',
            ),
            const SizedBox(height: 20),

            _section('1. Acceptance of Terms',
                'By downloading, installing or using the Workmate4u mobile app or website at workmate4u.com (the "Platform" or "Service"), you ("you" or "User") agree to be legally bound by these Terms of Service ("Terms") and our Privacy Policy. If you do not agree, do not use the Platform.\n\nThese Terms form a legally binding agreement between you and Workmate4u. They apply whether you act as a Task Poster, a Tasker, or simply browse the Platform.'),

            _section('2. Eligibility', null, bullets: [
              'Be at least 16 years of age;',
              'Be a resident of India and have the legal capacity to enter binding contracts under the Indian Contract Act, 1872;',
              'Not be barred from receiving services under applicable Indian law;',
              'Provide accurate, current and complete registration details (name, email, phone, date of birth and password, or a valid Google account).',
            ], preamble: 'To register or use Workmate4u, you must:'),
            _infoBox(
                '⚠️ Age requirement: Users below 16 years of age are not permitted to create or use a Workmate4u account.',
                isWarning: true),

            _section('3. Your Account', null, subsections: [
              _SubSection('3.1 Registration',
                  'You may register using either email + password or "Sign in with Google". You are responsible for keeping your credentials confidential and for every activity that occurs under your account.'),
              _SubSection('3.2 One Account Per User',
                  'Each individual may hold only one active Workmate4u account. Creating multiple accounts to defraud, evade fees, manipulate ratings or bypass suspensions is prohibited and may result in permanent termination and forfeiture of any wallet balance.'),
              _SubSection('3.3 Account Security',
                  'Notify us at info@workmate4u.com immediately if you suspect unauthorised access. Workmate4u is not responsible for losses arising from your failure to safeguard your credentials.'),
            ]),

            _section('4. What Workmate4u Is — and What It Is Not',
                'Workmate4u is an online intermediary marketplace that lets two types of users connect:',
                bullets: [
                  'Task Posters — users who post a task and pay for it to be completed.',
                  'Taskers — users who accept and complete the task in return for the agreed price.',
                ]),
            _infoBox(
                'Workmate4u only provides the technology platform (listings, matching, in-app chat and voice calls, payment routing through Razorpay, ratings, wallet ledger and dispute support). We are NOT a party to any agreement between a Task Poster and a Tasker, we are NOT the employer of any Tasker, and we do not perform tasks ourselves.\n\nThis Platform is provided in compliance with the Information Technology Act, 2000 and the IT (Intermediary Guidelines and Digital Media Ethics Code) Rules, 2021.'),

            _section('5. Posting & Accepting Tasks', null, subsections: [
              _SubSection('5.1 Task Posting Rules', null, bullets: [
                'Tasks must be lawful and clearly described.',
                'Minimum task budget is ₹100; maximum is ₹40,000 (subject to change with notice).',
                'Posters must have sufficient wallet balance to cover the task price plus the applicable service charge before posting.',
                'Posters must not request anything that discriminates based on caste, religion, gender, sexual orientation, disability or any other protected characteristic.',
              ]),
              _SubSection('5.2 Prohibited Tasks',
                  'You must not post or accept tasks that involve:',
                  bullets: [
                    'Anything illegal under Indian law, including narcotics, weapons, counterfeit goods, hawala, or money laundering;',
                    'Adult, sexual or escort services;',
                    'Activities that pose serious physical danger without licensed professional involvement;',
                    'Fraud, deception, phishing, doxxing, hacking or unauthorised data scraping;',
                    'Soliciting cash, gifts or off-Platform payments to circumvent service charges;',
                    'Hate speech, harassment, threats or content prohibited under the IT Rules, 2021.',
                  ]),
              _SubSection('5.3 Tasker Conduct',
                  'Taskers must complete tasks honestly, on time, and to the standard described. Misrepresentation of skills, identity or completion status may result in suspension and reversal of payment.'),
            ]),

            _section('6. Wallet, Service Charges & Payments', null,
                subsections: [
                  _SubSection('6.1 Workmate4u Wallet',
                      'Each user has an internal wallet ledger. Posters top up the wallet via Razorpay (UPI, cards, net-banking, wallets) before posting a task. The full task budget plus any applicable service charge is debited from the Poster\'s wallet at task creation and held by Workmate4u until task completion or cancellation.'),
                  _SubSection('6.2 Service Charges & Platform Commission',
                      'A service charge applies only for Delivery & Pick/Drop tasks (₹10–₹35 by distance; up to ₹40 for large items). All other categories have ₹0 service charge.\n\nPlatform commission on task completion:\n• Delivery, Pickup, Transport, Moving — 15% commission\n• All other categories — 17% commission\n\nThe Tasker sees their net estimated earnings before accepting any task.'),
                  _SubSection('6.3 Payouts to Taskers',
                      'On task completion confirmed by the Poster (or after the dispute window), the task earnings net of commission are credited to the Tasker\'s wallet. Payouts are processed via Razorpay subject to KYC verification.'),
                  _SubSection('6.4 Cancellations & Refunds', null, bullets: [
                    'If a task is cancelled before acceptance, the full amount (price + service charge) is refunded to the Poster\'s wallet.',
                    'If a Tasker abandons a task, the price is refunded; service charge may be retained at our discretion.',
                    'Disputes are reviewed within a reasonable timeframe; our decision is binding for releasing the held amount.',
                    'Razorpay fees on direct refunds may be deducted per Razorpay\'s policies.',
                  ]),
                  _SubSection('6.5 Negative Wallet Balance',
                      'If a wallet balance becomes negative, the account is automatically suspended until the user adds sufficient funds to bring the balance back to ₹0 or above.'),
                  _SubSection('6.6 Off-Platform Payments Prohibited',
                      'Requesting or paying any portion of the task price outside the Workmate4u Platform voids dispute protection and may result in permanent account termination.'),
                ]),

            _section('7. Communication, Voice Calls & Location',
                'The Platform offers in-app chat and WebRTC voice calls between matched users, displays approximate distance, and provides live tracking between Poster and Tasker while a task is in progress. Recording or distributing another user\'s voice/messages without consent is prohibited.'),

            _section('8. Ratings, Reviews & Reputation',
                'Both Posters and Taskers may rate each other after a task. Reviews must be honest and based on actual experience. We may remove reviews that are abusive, defamatory, paid, or violate these Terms.'),

            _section('9. User Conduct',
                'You agree NOT to:', bullets: [
              'Violate any applicable Indian law or third-party rights;',
              'Harass, threaten, stalk, dox or harm other users;',
              'Post false, misleading, defamatory, obscene or unlawful content;',
              'Use the Service for spam, malware or phishing;',
              'Reverse-engineer, scrape, or interfere with the Platform\'s operation;',
              'Circumvent service charges, ratings or suspensions;',
              'Impersonate another person or organisation.',
            ]),

            _section('10. Grievance & Content Takedown (IT Rules, 2021)',
                'If you believe any content on the Platform violates these Terms or applicable law, contact our Grievance Officer. Complaints are acknowledged within 24 hours and resolved within 15 days per Rule 3(2) of the IT (Intermediary Guidelines) Rules, 2021.',
                bullets: [
                  'Grievance Officer: Workmate4u Grievance Cell',
                  'Email: info@workmate4u.com',
                ]),

            _section('11. Intellectual Property',
                'The Workmate4u name, logo, source code, design, illustrations and all original content are owned by Workmate4u. You receive a limited, non-exclusive, non-transferable, revocable licence to use the Platform for personal, non-commercial purposes only.'),

            _section('12. Third-Party Services',
                'The Platform integrates with:', bullets: [
              'Razorpay — payment processing and payouts;',
              'Google Sign-In — for optional account login;',
              'SendGrid — for transactional email;',
              'Google Maps / device map apps — for navigation links;',
              'Netlify and Railway — for hosting infrastructure.',
            ]),

            _section('13. Disclaimers',
                'The Platform is provided on an "as-is" and "as-available" basis without warranties of any kind. Workmate4u does not warrant the conduct, identity or work quality of any User; that tasks will be completed safely; or that the Platform will be uninterrupted or error-free.'),

            _section('14. Limitation of Liability',
                'To the maximum extent permitted by law, Workmate4u shall not be liable for any indirect, incidental, consequential or punitive damages. Our aggregate liability for direct damages shall not exceed the total service charges you paid to Workmate4u in the three (3) months preceding the claim, or ₹5,000, whichever is lower.'),

            _section('15. Indemnification',
                'You agree to defend, indemnify and hold harmless Workmate4u from any claim, loss or expense arising out of (a) your breach of these Terms, (b) your violation of any law or third-party right, or (c) your acts or omissions in connection with any task on the Platform.'),

            _section('16. Termination',
                'You may request account deletion at any time from your profile or by emailing info@workmate4u.com. We may suspend or terminate your account immediately for any breach of these Terms, suspected fraud, or for legal reasons.'),

            _section('17. Governing Law & Dispute Resolution',
                'These Terms are governed by the laws of India. Disputes will first be resolved through good-faith discussion (30 days), then mediation, and finally binding arbitration under the Arbitration and Conciliation Act, 1996, seated in New Delhi. Indian courts at New Delhi shall have exclusive jurisdiction for matters not subject to arbitration.'),

            _section('18. Changes to These Terms',
                'Material changes will be notified by in-app notice at least 7 days before they take effect. Continued use of the Platform after the effective date constitutes acceptance of the updated Terms.'),

            _section('19. Contact Us', null, bullets: [
              'Email: info@workmate4u.com',
              'Website: https://workmate4u.com',
              'Operator: Workmate4u, India',
            ]),

            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE0E7FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Last Updated: May 22, 2026\nEffective Date: May 22, 2026',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF4338CA),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _header(String title, String subtitle, String date) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF0EA5E9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.gavel_rounded, color: Colors.white, size: 32),
          const SizedBox(height: 10),
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          Text(date,
              style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _section(String title, String? body,
      {String? preamble,
      List<String>? bullets,
      List<_SubSection>? subsections}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border(
                  left:
                      BorderSide(color: const Color(0xFF6366F1), width: 3)),
            ),
            child: Text(title,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B))),
          ),
          const SizedBox(height: 8),
          if (preamble != null) ...[
            _bodyText(preamble),
            const SizedBox(height: 6),
          ],
          if (body != null) _bodyText(body),
          if (bullets != null) _bulletList(bullets),
          if (subsections != null)
            ...subsections.map((s) => _renderSubSection(s)),
        ],
      ),
    );
  }

  Widget _renderSubSection(_SubSection s) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, left: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.title,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4338CA))),
          const SizedBox(height: 4),
          if (s.body != null) _bodyText(s.body!),
          if (s.bullets != null) _bulletList(s.bullets!),
        ],
      ),
    );
  }

  Widget _bodyText(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF475569),
                height: 1.6)),
      );

  Widget _bulletList(List<String> items) => Column(
        children: items
            .map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 5, left: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ',
                          style: TextStyle(
                              color: Color(0xFF6366F1),
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                      Expanded(
                          child: Text(item,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF475569),
                                  height: 1.5))),
                    ],
                  ),
                ))
            .toList(),
      );

  Widget _infoBox(String text, {bool isWarning = false}) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isWarning
              ? const Color(0xFFFEF3C7)
              : const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(10),
          border: Border(
              left: BorderSide(
                  color: isWarning
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFF6366F1),
                  width: 3)),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                color: isWarning
                    ? const Color(0xFF92400E)
                    : const Color(0xFF3730A3),
                height: 1.6)),
      );
}

class _SubSection {
  final String title;
  final String? body;
  final List<String>? bullets;
  const _SubSection(this.title, this.body, {this.bullets});
}
