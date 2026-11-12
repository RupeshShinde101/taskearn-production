import 'package:flutter/material.dart';
import '../../utils/legal_constants.dart';

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
            const SizedBox(height: 16),

            _infoBox(
              'STRICT 18+ ELIGIBILITY (DPDP ACT SECTION 9): Under Section 2(f) of India\'s Digital Personal Data Protection Act, 2023, anyone under 18 years of age is legally a "child". Workmate4u is exclusively for verified adults aged 18+. We never knowingly collect, track, profile, or retain personal data of anyone under 18.',
              isWarning: true,
            ),

            _section(
              '1. Introduction & Compliance Framework',
              'Workmate4u ("we", "us", "our") respects your privacy and processes personal data strictly in accordance with Indian law. This Privacy Policy explains what information we collect across the Workmate4u mobile app and website (https://workmate4u.com), why we process it, whom we share it with, how long we retain it, and your legal rights.\n\nThis Privacy Policy is published in compliance with Section 43A and Section 79 of the Information Technology Act, 2000, the IT (Reasonable Security Practices and Procedures and Sensitive Personal Data or Information) Rules, 2011 ("SPDI Rules"), the IT (Intermediary Guidelines and Digital Media Ethics Code) Rules, 2021, and India\'s Digital Personal Data Protection Act, 2023 ("DPDP Act, 2023").',
            ),

            _infoBox(
              'Summary: We collect only what is strictly required to verify your 18+ identity, match nearby tasks, process payments/withdrawals, and protect user safety. We NEVER sell personal data and NEVER run third-party advertising trackers.',
            ),

            _section('2. Data Fiduciary & Grievance Contact', null, bullets: [
              'Data Fiduciary / Operator: Workmate4u, India',
              'Website: https://workmate4u.com',
              'Privacy & Grievance Officer: Workmate4u Grievance Cell — info@workmate4u.com',
            ]),

            _section('3. Personal Data We Collect', null, subsections: [
              const _SubSection(
                '3.1 Registration, Profile & Age Verification Data',
                'Information you provide when registering or updating your profile:',
                bullets: [
                  'Full Name, Email Address (plus OTP verification state), and Mobile Number — identity, account security, task coordination, and transactional notices;',
                  'Date of Birth (DOB) — mandatory to verify that you are at least 18 years old under Indian law;',
                  'Terms Acceptance Timestamp & Version — legal audit trail of consent to these Terms and this Privacy Policy;',
                  'Optional Gender Selection ("male" / "female") — used solely to customize in-app illustration avatars if chosen;',
                  'Password (stored only as a salted PBKDF2-SHA256 hash, never plaintext) or Google Sign-In claims (email, name, profile photo URL, and Google account identifier);',
                  'Profile Photo, Bio, Active Profile Mode (Poster / Helper), Helper "My Skills", and Referral Code usage.',
                ],
              ),
              const _SubSection(
                '3.2 KYC Verification & Physical Onboarding Data (Sensitive Data)',
                'Collected when you verify identity or register for Sensitive Skills:',
                bullets: [
                  'Identity KYC: Selected document type (Aadhaar 12-digit, PAN 10-character, or Voter ID), document number, and uploaded front/back document photos — used strictly for identity authentication, anti-fraud, task eligibility, and payout compliance;',
                  'Physical Onboarding (Sensitive Skills: Cleaning, Delivery, Driving, Cooking, Plumbing, Electrical, Carpentry, Moving & Packing, Pet Care, Babysitting, Elder Care): Full legal name, complete residential address, primary and alternative emergency phone numbers, optional experience/driving-licence notes, and admin physical visit verification status.',
                ],
              ),
              const _SubSection(
                '3.3 Tasks, Completion Proof, Wallet & Bank Withdrawal Details',
                null,
                bullets: [
                  'Task Details: Task titles, descriptions, category/vehicle selections, Freelancer package/hourly options, pickup/drop/task addresses, saved locations, budgets, and platform fee ledgers;',
                  'Completion Proof Photos & Reviews: Camera/gallery proof photos submitted upon finishing a task, ratings, reviews, rank badges, and task release/abandonment counts;',
                  'Wallet Top-Ups: Processed by Razorpay Software Pvt. Ltd. We receive payment confirmation status, transaction reference IDs, and masked instrument summaries — we do NOT store card numbers, CVV, or UPI PINs;',
                  'Bank Withdrawal Details: Bank Name, Account Holder Name, 9–18 digit Bank Account Number, and 11-character IFSC Code collected over HTTPS to execute KYC-verified NEFT/IMPS/Razorpay payouts. If you opt to "Save payment details", those details are stored locally inside device app storage (SharedPreferences) solely for your convenience.',
                ],
              ),
              const _SubSection(
                '3.4 In-App Encrypted Chat & Optional Call Coordination',
                null,
                bullets: [
                  'Task Chat Messages & Images: Messages and photos exchanged in 1-on-1 task chat are transmitted over HTTPS/TLS with application-level task-room encryption (enc:v1:), and stored to deliver history and resolve safety or payment disputes;',
                  'External Dialer / Coordination Links: When active tasks surface a quick-dial ("Call") link, tapping it launches your device\'s telecom dialer or external app. Workmate4u does NOT record voice call audio; external carriers and apps operate under their own privacy policies.',
                ],
              ),
              const _SubSection(
                '3.5 Location, Notifications, Device & Technical Logs',
                null,
                bullets: [
                  'GPS Location (Coarse, Fine & Background where permitted): Used with your permission to find nearby tasks (~10 km matching), place map pins, estimate route distance, and enable live active-task tracking. Background location is accessed only when you grant OS permission for active Helper tracking and stops upon task completion or revocation;',
                  'Push Notifications: Firebase Cloud Messaging (FCM) device token and notification status for task alerts, chats, completions, and wallet updates;',
                  'Device & Security Telemetry: Device model, OS version, app version, IP address, API error logs, and rate-limiting logs to prevent spam, fraud, and DNS/network failures;',
                  'Local Storage (SharedPreferences): Caches your JWT authentication token, active session timestamp, profile cache, Poster/Helper mode, saved task addresses, and optional saved bank payout fields on your device.',
                ],
              ),
            ]),

            _section('4. How & Why We Process Your Data', null, bullets: [
              'Verify your 18+ legal age, email OTP, KYC identity, and Sensitive Skill physical onboarding;',
              'Create and maintain your Poster/Helper account and execute marketplace contracts;',
              'Match tasks using location proximity, configured Helper skills, and automated AI ranking convenience (never profiling minors);',
              'Facilitate task chat, proof verification, wallet payments, 20% fee/commission accounting, release-limit enforcement, negative-balance holds, and ₹100+ bank payouts;',
              'Prevent scam/illegal tasks, duplicate accounts, off-platform fee evasion, and fraud;',
              'Investigate safety reports, resolve payment/quality disputes, and honour user grievances;',
              'Fulfil statutory Indian legal duties (IT Act, Income Tax, GST, PMLA, RBI, and lawful court/police directions).',
            ]),
            _infoBox(
              'Lawful Basis (DPDP Act, 2023): Processing relies on your explicit informed consent (Section 6), contractual necessity for requested services, and statutory legitimate uses under Section 7 (compliance with Indian law, court orders, fraud prevention, and safety enforcement).',
            ),

            _section('5. How Information Is Shared', null, subsections: [
              const _SubSection(
                '5.1 With Other Verified Users',
                'Your display name, avatar, rank, rating, and general area appear on tasks and offers. Once matched, necessary task address details, in-app chat, and (where enabled for active execution) phone coordination options are shared between the Poster and assigned Helper.',
              ),
              const _SubSection('5.2 With Service Providers & Infrastructure Partners', null, bullets: [
                'Razorpay Software Pvt. Ltd. — wallet top-ups, bank payouts, and payment fraud screening;',
                'Google LLC — Google Sign-In authentication, Google Play Services Geocoder, Google Maps navigation links, and DNS-over-HTTPS fallback (dns.google);',
                'Google Firebase (FCM) — real-time push notifications;',
                'Twilio SendGrid — email OTP verification and transactional email delivery;',
                'Railway & Netlify — managed cloud servers, PostgreSQL database hosting, and web CDN;',
                'OpenStreetMap Nominatim, Komoot Photon & OSRM — HTTPS address autocomplete, geocoding, and road-distance estimation (receives search coordinates/query text & device IP);',
                'Cloudflare DoH (cloudflare-dns.com) — encrypted DNS fallback to keep connectivity working when carrier DNS fails.',
              ]),
              const _SubSection(
                '5.3 Legal, Regulatory & Safety Disclosures',
                'We may disclose records when strictly necessary to comply with lawful Indian court orders, police/cyber-crime requisitions under the IT Act or BNSS/BNS, tax/PMLA audits, or to investigate suspected child/adolescent exploitation, violence, or financial fraud.',
              ),
            ]),
            _infoBox(
              'Zero Data Brokering: Workmate4u does NOT sell personal data, rent contact lists, or embed third-party ad-tech SDKs.',
            ),

            _section(
              '6. International Data Transfers',
              'While our primary service targets India, certain cloud/messaging partners (such as Google/Firebase or SendGrid) may process data on servers outside India. All cross-border transfers comply with Section 16 of the DPDP Act, 2023 and applicable Government of India notifications.',
            ),

            _section('7. Data Security & Breach Response', null, bullets: [
              'HTTPS / TLS encryption across all client-server API and Socket.IO traffic;',
              'Passwords hashed using salted PBKDF2-SHA256; signed JWT tokens stored in app storage;',
              'Task chat safeguarded via TLS + task-room application encryption (enc:v1:);',
              'Restricted role-based access controls, audit logging, and automated rate-limiting on backend servers;',
              'PCI-DSS compliant card/UPI processing solely on Razorpay\'s infrastructure;',
              'In the unlikely event of a personal data breach, we will notify affected Users and the Data Protection Board of India promptly as mandated under Section 8(6) of the DPDP Act, 2023.',
            ]),

            _section('8. Data Retention Schedule', null),
            _retentionTable(),

            _section(
              '9. Your Rights Under the DPDP Act, 2023 & Account Deletion',
              'As a Data Principal in India, you may exercise the following rights:',
              bullets: [
                'Right to Access Information (s. 11): Request a summary of your personal data processed and third parties with whom it was shared;',
                'Right to Correction, Completion & Updating (s. 12): Update profile details in-app or request correction of inaccurate records;',
                'Right to Erasure / Withdraw Consent (s. 12 & s. 6): Delete your account via Profile → Delete My Account or email info@workmate4u.com. Account deletion cannot complete while active tasks, open disputes, or negative wallet balances exist, and financial, KYC, tax, and fraud-prevention records required under Indian law are preserved strictly in restricted archive until statutory expiry;',
                'Right to Nominate (s. 14): Designate an adult nominee to exercise data rights in case of incapacity or death by emailing info@workmate4u.com;',
                'Right of Grievance Redressal & Appeal (s. 13): Contact our Grievance Officer first; unresolved grievances may be escalated to the Data Protection Board of India.',
              ],
            ),

            _section(
              '10. Zero Tolerance for Children\'s & Minor Data (Under 18)',
              'Under Section 2(f) and Section 9 of the DPDP Act, 2023, any person below eighteen (18) years of age is a child. Workmate4u does NOT target, onboard, profile, monitor, or knowingly process data of individuals under 18. Date-of-birth gates restrict registration strictly to 18+ adults. If we learn that an account belongs to or is operated by someone under 18, we immediately suspend access, terminate the account, and erase non-statutory personal data (retaining only minimum fraud/compliance block identifiers where legally required). Please report any suspected underage user immediately to info@workmate4u.com.',
            ),

            _section('11. Device Permissions & Local Storage', null, bullets: [
              'Location: Nearby task matching, pickup/drop distance, map pin selection, and active-task tracking (manageable anytime in Android Settings);',
              'Camera & Photos/Media: Profile avatars, KYC Aadhaar/PAN/Voter ID documents, and task completion proof photos;',
              'Notifications: Real-time task alerts, chat replies, and payment confirmations;',
              'Local Storage: Used strictly for login session persistence, saved task locations, mode state, and optional saved payout fields — never for ad tracking.',
            ]),

            _section('12. Grievance & Data Protection Officer', null, bullets: [
              'Designation: Workmate4u Grievance Cell',
              'Email: info@workmate4u.com',
              'Website: https://workmate4u.com',
              'Timeline: Acknowledged within 24 hours; resolved within 15 days under IT Rules 2021 / statutory DPDP grievance timelines.',
            ]),

            _section(
              '13. Changes to This Privacy Policy',
              'We may update this Privacy Policy periodically to reflect new app features or Indian regulatory requirements. Material updates will be notified in-app at least 7 days prior to taking effect.',
            ),

            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFD1FAE5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Last Updated: $kLegalEffectiveDate\nEffective Date: $kLegalEffectiveDate\nPolicy Version: $kTermsVersion',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF065F46),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
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
          Text('How Workmate4u collects, verifies, uses & protects your data (18+ Only).',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          SizedBox(height: 8),
          Text(
            'Effective Date: $kLegalEffectiveDate  •  IT Act 2000 & DPDP Act 2023',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _retentionTable() {
    const rows = [
      ['Account profile & DOB verification', 'While active + 30 days backup purge'],
      ['KYC (Aadhaar/PAN/Voter ID) & Physical Onboarding records', 'Active status + up to 8 years (PMLA / anti-fraud audit)'],
      ['Wallet, Razorpay & bank withdrawal records', 'Up to 8 years (Income Tax / PMLA / RBI regulations)'],
      ['Task records, completion proof photos, chat & reviews', 'Up to 5 years (disputes, safety & tax)'],
      ['Live task GPS tracking coordinates', 'Task lifecycle only (stops on completion)'],
      ['Server security & API access logs', 'Up to 12 months'],
      ['Grievance & support tickets', 'Up to 3 years (or final legal resolution)'],
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
            width: double.infinity,
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

  Widget _infoBox(String text, {bool isWarning = false}) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:
              isWarning ? const Color(0xFFFEF3C7) : const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(10),
          border: Border(
              left: BorderSide(
                  color: isWarning
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFF10B981),
                  width: 3)),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                color: isWarning
                    ? const Color(0xFF92400E)
                    : const Color(0xFF065F46),
                height: 1.6)),
      );
}

class _SubSection {
  final String title;
  final String? body;
  final List<String>? bullets;
  const _SubSection(this.title, this.body, {this.bullets});
}
