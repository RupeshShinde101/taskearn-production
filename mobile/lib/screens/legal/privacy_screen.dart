import 'package:flutter/material.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF10B981),
        foregroundColor: Colors.white,
        title: const Text('Privacy Policy',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            const SizedBox(height: 20),

            _section('1. Introduction',
                'Workmate4u ("we", "us" or "our") respects your privacy. This Privacy Policy explains what personal information we collect when you use the Workmate4u mobile app ("Platform"), how we use it, who we share it with, and the rights you have over it. It applies to Task Posters, Taskers and visitors.\n\nThis policy is published in compliance with Section 43A of the Information Technology Act, 2000, the IT (Reasonable Security Practices and Procedures and Sensitive Personal Data or Information) Rules, 2011, and the Digital Personal Data Protection Act, 2023 ("DPDP Act, 2023").'),

            _infoBox(
                '✅ Plain summary: We collect only what is needed to run the marketplace, payments and safety features. We never sell your data. We do not run third-party advertising trackers.'),

            _section('2. Data Controller / Fiduciary', null, bullets: [
              'Operator: Workmate4u, India',
              'Email: info@workmate4u.com',
              'Grievance & Data Protection Officer: Workmate4u Grievance Cell — info@workmate4u.com',
            ]),

            _section('3. Information We Collect', null, subsections: [
              _SubSection('3.1 Information you provide directly',
                  'We collect the following data when you register or use the app:',
                  bullets: [
                    'Full name — account identity, ratings, communication between task parties.',
                    'Email address — login and transactional email (task updates, receipts, password reset).',
                    'Phone number — account verification and in-app communication.',
                    'Date of birth — to verify the 16+ age requirement.',
                    'Password — stored only as a salted PBKDF2-SHA256 hash; never in plain text.',
                    'Google account profile (if you use Sign-in with Google) — email, name, profile picture and a Google sub-ID.',
                    'Profile details, photo, bio, skills — Tasker discoverability and trust.',
                    'Task details (description, photos, address, price) — to match Posters with Taskers.',
                    'Reviews & ratings — reputation system.',
                    'Support tickets, chat & voice-call metadata — customer support and dispute resolution.',
                    'UPI/bank details for payouts (Taskers) — collected and stored by Razorpay; we hold only a token reference.',
                  ]),
              _SubSection('3.2 Information collected automatically', null,
                  bullets: [
                    'Device data: device model, OS version, app version, language.',
                    'Approximate & precise location: only when you grant app permission — used for nearby task matching, distance display and live tracking during a task.',
                    'Usage data: features used, error logs, timestamps.',
                    'IP address: for security, fraud prevention and abuse-rate limiting.',
                  ]),
              _SubSection('3.3 Information from third parties', null,
                  bullets: [
                    'Google (if you use Sign-in with Google) — basic profile claims.',
                    'Razorpay — payment status, last-4 digits / instrument type, refund/chargeback events. We do NOT receive your full card or bank credentials.',
                  ]),
            ]),

            _section('4. How We Use Your Information',
                'We process personal data to:', bullets: [
              'Create and operate your account and the marketplace;',
              'Match Posters and Taskers and enable in-app chat & voice calls;',
              'Process wallet top-ups, task payments, service charges, platform commission deductions and Tasker payouts via Razorpay;',
              'Send essential transactional notifications (task accepted, payment receipt, commission statement, password reset);',
              'Show approximate distance and (with your consent) live tracking during a task;',
              'Maintain ratings, reviews and trust signals;',
              'Detect and prevent fraud, abuse and security incidents;',
              'Provide customer support and handle grievances;',
              'Improve performance, fix bugs and develop new features;',
              'Comply with legal obligations (tax, anti-money-laundering, court orders, lawful government requests).',
            ]),
            _infoBox(
                'Lawful basis (DPDP Act, 2023): primarily your consent and the necessity of processing for performance of the contract you enter into with us by using the Platform.'),

            _section('5. Who We Share Information With', null, subsections: [
              _SubSection('5.1 With other users',
                  'Your display name, profile photo, ratings and approximate location are visible on the Platform. After a Tasker accepts a task, both parties\' phone numbers and exact task location may be shared between them to enable the task.'),
              _SubSection('5.2 With service providers', null, bullets: [
                'Razorpay Software Pvt. Ltd. — payment gateway, KYC for payouts, fraud screening.',
                'Google LLC — Sign-In authentication and Google Maps navigation links.',
                'Twilio SendGrid — transactional email delivery.',
                'Netlify — frontend hosting & CDN.',
                'Railway — backend hosting and managed PostgreSQL database.',
              ]),
              _SubSection('5.3 With law enforcement / regulators',
                  'When required by a valid Indian court order or to comply with applicable law (including the IT Act and IT Rules, 2021), or where necessary to investigate fraud, prevent harm or enforce our Terms.'),
            ]),
            _infoBox(
                '🔒 We do not sell your data. We do not share your personal data with advertising networks or data brokers, and we do not run third-party ad trackers on the Platform.'),

            _section('6. International Transfers',
                'Some service providers (e.g. Google, SendGrid) operate servers outside India. Where personal data is transferred outside India, we rely on the providers\' contractual safeguards and on transfers permitted under the DPDP Act and applicable Government of India notifications.'),

            _section('7. Data Security', null, bullets: [
              'All traffic between your device and our servers is encrypted via HTTPS / TLS.',
              'Passwords are stored only as salted PBKDF2-SHA256 hashes.',
              'Authentication uses signed JWT tokens stored on the user\'s device.',
              'The database is hosted in a managed environment with access restricted to authorised personnel.',
              'Payment card and bank details are never stored on our servers — they are handled directly by Razorpay (PCI-DSS compliant).',
              'We monitor for abuse and apply rate-limiting and audit logging.',
            ]),
            _infoBox(
                '⚠️ No system can be guaranteed 100% secure. In the event of a personal data breach, we will notify you and the Data Protection Board of India in line with the DPDP Act, 2023.'),

            _section('8. Data Retention', null),
            _retentionTable(),

            _section('9. Your Rights Under the DPDP Act, 2023',
                'Under the Digital Personal Data Protection Act, 2023 you have the right to:',
                bullets: [
                  'Access: obtain a summary of the personal data we hold about you.',
                  'Correction & Erasure: request correction of inaccurate data or deletion of your account and personal data.',
                  'Grievance Redressal: lodge a complaint with our Data Protection Officer.',
                  'Nominate a Nominee: nominate a person to exercise rights on your behalf in the event of incapacity or death.',
                  'Appeal: escalate to the Data Protection Board of India if your grievance is not resolved.',
                ]),
            _infoBox(
                'To exercise these rights, email info@workmate4u.com with your registered email address and the specific request.'),

            _section('10. Children\'s Privacy',
                'The Platform is not intended for children under 16 years of age. We do not knowingly collect personal data from anyone under 16. If we discover that a user is under 16, we will delete their account and associated data promptly.'),

            _section('11. Push Notifications',
                'The Workmate4u app may send you push notifications about task updates, payments and important alerts. You can manage notification preferences in your device settings at any time.'),

            _section('12. Location Data',
                'Precise location is requested only when you begin a task or browse nearby tasks. You may revoke location permission from your device settings at any time, but some features (nearby matching, live tracking) will be unavailable without it.'),

            _section('13. Cookies & Local Storage',
                'The mobile app uses local storage (SharedPreferences, secure storage) to keep you logged in and cache app data. No third-party advertising cookies are used. For the website, see our Cookie Policy at workmate4u.com/cookies.html.'),

            _section('14. Grievance Officer',
                'If you have questions or complaints about this Privacy Policy or our data practices:', bullets: [
              'Name: Workmate4u Grievance Cell',
              'Email: info@workmate4u.com',
              'Website: https://workmate4u.com',
              'Response time: within 24 hours of receipt; resolution within 30 days.',
            ]),

            _section('15. Changes to This Policy',
                'We may update this Privacy Policy from time to time. Material changes will be notified via in-app notice at least 7 days before they take effect. Continued use of the Platform after the effective date constitutes acceptance of the updated policy.'),

            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFD1FAE5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Last Updated: May 22, 2026\nEffective Date: May 22, 2026',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF065F46),
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

  Widget _header() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF10B981), Color(0xFF0EA5E9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_rounded, color: Colors.white, size: 32),
          SizedBox(height: 10),
          Text('Privacy Policy',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          SizedBox(height: 4),
          Text('How we collect, use, and protect your information.',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          SizedBox(height: 8),
          Text('Compliant with IT Act 2000 & DPDP Act 2023',
              style: TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _retentionTable() {
    const rows = [
      ['Account profile', 'Until deletion + 30 days in backups'],
      ['Task records, chat & reviews', 'Up to 5 years (disputes & tax)'],
      ['Wallet & payment records', 'Up to 8 years (financial regulations)'],
      ['Voice-call signalling metadata', 'Up to 90 days (no audio recorded)'],
      ['Server access logs', 'Up to 12 months'],
      ['Support tickets', 'Up to 3 years'],
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: const Row(
              children: [
                Expanded(
                    flex: 2,
                    child: Text('Data Type',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: Color(0xFF1E293B)))),
                Expanded(
                    flex: 2,
                    child: Text('Retention Period',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: Color(0xFF1E293B)))),
              ],
            ),
          ),
          ...rows.asMap().entries.map((e) => Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: e.key.isEven ? Colors.white : const Color(0xFFF8FAFC),
                  border: const Border(
                      top: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: Row(
                  children: [
                    Expanded(
                        flex: 2,
                        child: Text(e.value[0],
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF475569)))),
                    Expanded(
                        flex: 2,
                        child: Text(e.value[1],
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF475569)))),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _section(String title, String? body,
      {List<String>? bullets, List<_SubSection>? subsections}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: const Border(
                  left: BorderSide(color: Color(0xFF10B981), width: 3)),
            ),
            child: Text(title,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B))),
          ),
          const SizedBox(height: 8),
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
                  color: Color(0xFF059669))),
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
                fontSize: 13, color: Color(0xFF475569), height: 1.6)),
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
                              color: Color(0xFF10B981),
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

  Widget _infoBox(String text) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(10),
          border: const Border(
              left: BorderSide(color: Color(0xFF10B981), width: 3)),
        ),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12, color: Color(0xFF065F46), height: 1.6)),
      );
}

class _SubSection {
  final String title;
  final String? body;
  final List<String>? bullets;
  const _SubSection(this.title, this.body, {this.bullets});
}
