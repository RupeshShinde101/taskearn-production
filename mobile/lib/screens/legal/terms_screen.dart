import 'package:flutter/material.dart';
import '../../utils/legal_constants.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF6366F1),
        foregroundColor: Colors.white,
        title: const Text('Terms & Conditions',
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
              'Terms of Service & Conditions',
              'Binding Legal Agreement governing all use of Workmate4u in India.',
              'Effective Date: $kLegalEffectiveDate  •  Version: $kTermsVersion',
            ),
            const SizedBox(height: 16),

            _infoBox(
              'STRICT 18+ ADULTS ONLY PLATFORM (INDIA): Under the Indian Majority Act, 1875, Indian Contract Act, 1872, Child and Adolescent Labour (Prohibition and Regulation) Act, 1986, Motor Vehicles Act, 1988, and DPDP Act, 2023, anyone below 18 years of age is strictly prohibited from registering, browsing as a member, posting tasks, accepting tasks, or performing or assisting in any task directly or indirectly.',
              isWarning: true,
            ),

            _section(
              '1. Acceptance of Terms',
              'By downloading, accessing, registering on, or using the Workmate4u mobile application or website at https://workmate4u.com (collectively, the "Platform" or "Service"), you ("User", "you") agree to be legally bound by these Terms of Service and Terms & Conditions ("Terms") together with our Privacy Policy.\n\nThese Terms form an enforceable electronic contract under the Information Technology Act, 2000 between you and Workmate4u ("Workmate4u", "we", "us", "our"). They apply equally whether you browse, act as a Task Poster ("Poster Mode"), act as a Service Helper ("Helper Mode"), or submit verification or payment details. If you do not agree, stop using and uninstall the Platform immediately.',
            ),

            _section(
              '2. 18+ Eligibility, Legal Capacity & Zero Child / Adolescent Labour',
              null,
              preamble: 'To register, hold an account, post tasks, or perform tasks on Workmate4u, you continuously represent, warrant, and covenant that:',
              bullets: [
                'Age 18+ Mandatory: You are at least eighteen (18) years of completed age under Section 3 of the Indian Majority Act, 1875 and possess full legal competence to contract under Section 11 of the Indian Contract Act, 1872;',
                'Indian Residency & Lawful Status: You reside in India and are not prohibited under Indian law from entering service engagements or financial transactions;',
                'Truthful Registration: All identity, contact, Date of Birth (DOB), KYC, and physical onboarding details provided by you are accurate, current, and solely your own;',
                'Strict Child & Adolescent Labour Prohibition: You will NEVER permit, bring, recruit, hire, or subcontract any person under 18 years of age ("child" or "adolescent" under the Child and Adolescent Labour (Prohibition and Regulation) Act, 1986, as amended in 2016, the Juvenile Justice Act, 2015, and the Bharatiya Nyaya Sanhita, 2023) to perform, assist with, ride along on, or handle any task booked through the Platform;',
                'No Solicitation of Underage Work: Posters must NEVER post tasks inviting, requiring, or facilitating work by minors (<18);',
                'Immediate Remedies for Age Misrepresentation: Any account created using a false DOB, another person\'s identity, or used by a person under 18 is void ab initio. Workmate4u reserves the right to immediately and permanently terminate the account, freeze/forfeit unlawful promotional credits, withhold disputed funds pending investigation, report serious violations to statutory authorities, and seek full indemnification from the misrepresenting user and/or responsible adult guardian.',
              ],
            ),

            _section('3. Accounts, Verification (KYC) & Physical Onboarding', null, subsections: [
              const _SubSection(
                '3.1 Single Account & Credentials',
                'You may register via Email + Password or Google Sign-In, followed by mandatory DOB (18+), phone number, and explicit acceptance of these Terms and the Privacy Policy. Only one account per adult individual is permitted. Creating duplicate accounts to evade bans, penalties, negative balances, or farm referral bonuses is prohibited and results in immediate suspension and forfeiture of promotional credits. You are solely responsible for all activity occurring under your login session.',
              ),
              const _SubSection(
                '3.2 Mandatory Identity KYC & Email OTP Verification',
                'Posting tasks, accepting restricted tasks, and requesting bank withdrawals require a verified email address (6-digit OTP) and approved KYC Verification (Aadhaar 12-digit, PAN 10-character, or Voter ID number plus front/back document photos). Submitting altered, borrowed, stolen, or fraudulent KYC documents leads to immediate permanent ban, payout block, and potential reporting to law enforcement.',
              ),
              const _SubSection(
                '3.3 Physical Onboarding for Sensitive Skills (Helper Mode)',
                'Helpers selecting any of the eleven (11) Sensitive Skills — Cleaning, Delivery, Driving, Cooking, Plumbing, Electrical, Carpentry, Moving & Packing, Pet Care, Babysitting, or Elder Care — must complete Admin Physical Onboarding by supplying authentic Legal Name, Complete Residential Address, Primary & Alternative Phone Numbers, relevant licence/experience remarks, and consenting to in-person physical verification by an authorized Workmate4u representative.',
              ),
              const _SubSection(
                '3.4 No Warranty From Verification Checks',
                'KYC review and Physical Onboarding are administrative risk-mitigation steps performed at a point in time based on user-submitted records. Workmate4u does NOT issue police clearance certificates, criminal background guarantees, medical fitness certifications, or continuing supervision over any Helper or Poster. Both parties remain solely responsible for verifying identity and exercising prudent personal safety precautions on-site.',
              ),
            ]),

            _section(
              '4. Legal Role — Pure Technology Intermediary & Non-Employment',
              'Workmate4u operates strictly as a technology marketplace enabling dual-mode adult users to connect:',
              bullets: [
                'Poster Mode: Adult Users posting lawful tasks and paying for verified completion;',
                'Helper Mode: Adult Users configuring "My Skills" (strictly for Helper discovery and automated local alerts within ~10 km) to accept and execute tasks;',
                'Automated Suggestions & Ranks: AI-suggested task matching, distance filters, Live Nearby feeds, and reputation tiers (New, Bronze, Silver, Gold, Platinum, Elite) are automated informational tools only — NOT endorsements, warranties, or guarantees.',
              ],
            ),
            _infoBox(
              'IT ACT SECTION 79 SAFE HARBOUR & NON-EMPLOYMENT DISCLAIMER: Workmate4u acts solely as an online "intermediary" under Section 2(1)(w) and Section 79 of the Information Technology Act, 2000 and the IT (Intermediary Guidelines and Digital Media Ethics Code) Rules, 2021. Workmate4u is NOT the employer, principal employer, contractor, agent, joint venturer, insurer, or custodian of any Helper or Poster under the Code on Wages, 2019, Industrial Relations Code, EPF Act, 1952, ESI Act, 1948, Employees\' Compensation Act, 1923, or Contract Labour (Regulation and Abolition) Act, 1970. Every Helper operates strictly as an independent self-employed service provider controlling their own tools, schedule, routes, and task selection.',
            ),

            _section('5. Task Categories, Pricing, Pass-Through Costs & Task Rules', null, subsections: [
              const _SubSection(
                '5.1 Category Minimums, Distance Rates & Freelancer Quotes',
                null,
                bullets: [
                  'Delivery, Pickup, Transport & Moving: Minimum quotes scale dynamically by vehicle and route/Haversine distance — e.g., Bike Delivery (₹12/km, min ₹24), Rikshaw Delivery / Auto Pickup (₹18/km, min ₹30), Transport (₹18/km, min ₹50), and Moving & Packing (₹400 base + ₹35/km). Road tolls, parking, and statutory levies are excluded unless expressly included.',
                  'Home, Care, Errands & Local Services: Subject to dynamic category-based minimums (starting from ₹100 for Groceries/Laundry/Other up to ₹1,500 for Photography) and platform budget caps shown before posting.',
                  'Freelancer & Digital Tasks (Web/App & Tech, Design & Creative, Video & Audio, Content & Marketing, Business & Admin): Support Dual Pricing — Per Project / Package / Unit OR Hourly Rate (capped at platform limits displayed in-app).',
                  'Separate Client-Paid Third-Party Costs (Freelance & Errands): Domain names, hosting/cloud servers, paid APIs, SaaS subscriptions, stock media/font/music licences, commercial printing, paid ad wallet spend, government portal fees, and physical purchases/groceries requested by the Poster are paid separately by the Poster and are excluded from base budget and platform fees unless otherwise stated.',
                ],
              ),
              const _SubSection(
                '5.2 Strictly Prohibited Tasks & Content',
                'You may NEVER post, accept, or facilitate tasks involving:',
                bullets: [
                  'Anything illegal under Indian law (Bharatiya Nyaya Sanhita / IPC, NDPS narcotics/drugs, Arms Act weapons, smuggling, stolen or counterfeit goods, hawala, money laundering, or forged documents/certificates);',
                  'Any task involving, targeting, exploiting, or delegating labour to minors under 18 years of age;',
                  'Adult, sexual, escort, or obscene content or services;',
                  'Financial scams, crypto/forex investment schemes, gambling/betting, unregulated loans, MLM/pyramid/Ponzi schemes, money-mule transfers, gift-card/wire-transfer scams, or upfront security/joining fees charged to Helpers;',
                  'OTP/PIN/CVV/net-banking credential sharing, Aadhaar/PAN/bank/UPI account renting, bulk email/social account creation, fake reviews/likes/followers/bot clicks, phishing, hacking, or exam cheating;',
                  'Hazardous chemical, electrical, structural, or medical work undertaken without required statutory licences and safety equipment;',
                  'Publishing phone numbers, email addresses, or external contact handles inside public task posts, or soliciting off-platform cash/UPI settlement to evade platform fees.',
                ],
              ),
              const _SubSection(
                '5.3 Helper Execution, Proof of Completion & Release Penalties',
                null,
                bullets: [
                  'One Active Task Limit: To maintain reliability, a Helper may hold only one (1) active accepted task at a time unless otherwise enabled.',
                  'Completion Proof Photo: Helpers must upload genuine, contemporaneous photographic proof before marking work complete. Uploading blank, fake, recycled, or deceptive images constitutes fraud.',
                  'Task Abandonment Penalty & Daily Limit: Releasing or abandoning an accepted task may incur an automatic 10% release penalty debited from the Helper\'s wallet. Exceeding three (3) task releases within a rolling 24-hour window triggers an automatic 48-hour account suspension; repeated abuse causes permanent termination.',
                ],
              ),
            ]),

            _section('6. Wallet, Verify-Then-Pay Flow, Fees & Withdrawals', null, subsections: [
              const _SubSection(
                '6.1 Workmate4u Wallet & Verify-Then-Pay Checkout',
                'Wallet top-ups are processed securely through Razorpay (UPI, cards, net-banking, supported wallets). When posting a task, no upfront wallet debit is taken at creation; instead, the Poster enters a binding payment commitment. Upon the Helper completing the task and submitting completion proof, the Poster must inspect and promptly tap "Verify & Pay Now" to settle the full payable amount from their Wallet (topping up via Razorpay if needed). Refusing or delaying verification in bad faith after satisfactory completion is a breach of these Terms; Workmate4u may restrict account features, adjudicate disputes, debit available funds, or enforce a negative-balance recovery.',
              ),
              const _SubSection(
                '6.2 Transparent Platform Fees (Inclusive of GST)',
                'Displayed upfront before posting or accepting every task:\n'
                '• Poster Platform Fee: 20% of the agreed task budget (inclusive of applicable GST), plus any shown category/service charge (currently ₹0 where displayed).\n'
                '• Helper Platform Commission: 20% of the agreed task budget (inclusive of applicable GST), deducted from the gross payout upon settlement.',
              ),
              const _SubSection(
                '6.3 Bank Withdrawals to KYC-Verified Users',
                'Helpers may request payout of eligible Wallet earnings (minimum ₹100) only after Email and KYC Verification are approved. Valid Indian banking details (Bank Name, Account Holder Name, 9–18 digit Account Number, and 11-character IFSC) are required and processed via NEFT/IMPS/Razorpay payouts typically within 24–48 hours, subject to bank holidays, anti-money-laundering (PMLA) checks, and open dispute holds.',
              ),
              const _SubSection(
                '6.4 Cancellations, Chargebacks, Lien & Negative Balance',
                null,
                bullets: [
                  'Pre-acceptance cancellations incur no task payout charge.',
                  'Once a task is accepted and work commences, cancellation, partial completion, or quality disputes are adjudicated by Workmate4u support using completion photos, GPS/timeline logs, and chat records; our administrative ledger decision is final for Wallet settlement within the Platform.',
                  'Payment gateway reversals, chargebacks, confirmed fraud refunds, or release penalties may be set off against Wallet balance and may create a negative balance.',
                  'Negative Balance Suspension: If your Wallet balance falls below ₹0, your account is automatically suspended (blocking task actions and withdrawals) until you top up sufficient funds to restore a non-negative balance.',
                  'Off-Platform Payment Prohibition: Demanding, offering, or making direct cash/UPI/bank payment outside Workmate4u voids all dispute resolution, refund protection, and payment guarantees and warrants permanent termination.',
                ],
              ),
            ]),

            _section(
              '7. In-App Encrypted Chat & Active-Task Coordination Calls',
              'To keep task coordination transparent and protect private details:',
              bullets: [
                'Primary Official Channel: Task instructions, location clarifications, scope changes, and proof confirmation should be recorded inside the 1-on-1 in-app task chat (protected by HTTPS/TLS transport encryption and task-room application-level encryption enc:v1:).',
                'Active-Task Voice / Messaging Shortcuts: For an active assigned task where phone contact is surfaced, the app may provide quick "Call" (device dialer) or messaging handoffs strictly for logistics and arrival coordination. Publicly posting phone numbers/emails in open listings or soliciting off-platform fee circumvention remains strictly banned.',
                'Safety & Dispute Audits: If a user files a complaint, fraud report, safety alert, or payment dispute, Workmate4u may access and review relevant task chat logs, uploaded photos, and metadata.',
                'Communication Conduct: Harassment, hate speech, threats, extortion, unsolicited advances, or secret recording/redistribution of chats or calls without consent is strictly forbidden. Workmate4u bears zero liability for anything communicated over carrier voice calls, SMS, or external third-party messaging apps.',
              ],
            ),

            _section('8. Assumption of Physical Risk, Premises Safety & Statutory Licences', null, subsections: [
              const _SubSection(
                '8.1 Physical, Premises & Personal Safety Release',
                'In-person tasks (Delivery, Driving, Moving, Electrical, Plumbing, Carpentry, Cooking, Cleaning, Care, Errands) involve real-world hazards including road accidents, lifting injuries, electric/chemical exposure, food allergies, animal bites, property damage, and interpersonal risks. Posters and Helpers participate strictly at their own risk. To the fullest extent permitted by law, you irrevocably release Workmate4u, its founders, employees, and affiliates from claims arising out of bodily injury, death, illness, property loss, theft, or third-party liability connected to any task.',
              ),
              const _SubSection(
                '8.2 Mandatory Licences, Vehicles & Road Compliance',
                'Helpers accepting Driving, Delivery, Pickup, Transport, or Moving tasks solely warrant that they are 18+ years old and hold a valid Indian Driving Licence, Vehicle Registration Certificate (RC), valid motor insurance, and Pollution Under Control (PUC) certificate, and will obey all traffic laws. Helpers accepting skilled trade/care/freelance tasks solely warrant they hold required competence, safety gear, and legal permits.',
              ),
              const _SubSection(
                '8.3 Domestic Care Categories (Babysitting, Elder Care, Pet Care)',
                'While Helpers in all categories must strictly be 18+, Posters using Babysitting, Child Care, Elder Care, or Pet Care remain solely responsible as parents, legal guardians, or owners for conducting independent verification, remaining reachable for emergencies, disclosing allergies/medical needs, and ensuring safe home supervision. Workmate4u is neither a childcare facility nor a healthcare provider.',
              ),
            ]),

            _section(
              '9. Freelancer Deliverables, Intellectual Property & User Taxes',
              null,
              bullets: [
                'Deliverable Originality & Transfer: Freelancers warrant that delivered code, designs, videos, texts, and media are original (or properly licensed) and do not infringe third-party rights. Agreed copyright/usage rights transfer to the Poster only upon full verified payment settlement on Workmate4u.',
                'User Tax Compliance: Users are solely responsible for declaring income and complying with the Income-tax Act, 1961 (including TDS if applicable) and GST laws on their own services or receipts. Workmate4u\'s 20% fee/commission includes GST chargeable on Workmate4u\'s platform fee alone.',
              ],
            ),

            _section('10. Account Suspension, Termination & Account Deletion', null, bullets: [
              'Voluntary Deletion: You may delete your account in-app (Profile → Delete My Account) or via info@workmate4u.com, provided you have no active/pending tasks, no unresolved disputes, and a non-negative Wallet balance (withdraw eligible funds ₹100+ beforehand).',
              'Mandatory Retention on Deletion: Even after account deletion, Workmate4u retains transaction ledgers, KYC/onboarding audit records, and tax/fraud logs for up to 8 years (or longer if under dispute/legal hold) as required by Indian law.',
              'Platform Enforcement: We may immediately suspend or permanently terminate any account for underage (<18) status, fake KYC/DOB, safety complaints, exceeding release limits, negative balance, scam tasks, or breach of these Terms.',
            ]),

            _section(
              '11. Intellectual Property & Acceptable Technical Use',
              'All Workmate4u trademarks, logos, app design, source code, illustrations, encryption formats, and database compilations belong exclusively to Workmate4u. You may not scrape, crawl, reverse-engineer, decompile, overload, bypass rate limits/security controls, or exploit the Platform commercially outside authorized task participation.',
            ),

            _section(
              '12. Third-Party Services & Infrastructure',
              'The Platform relies on independent third-party providers including Razorpay Software Pvt. Ltd. (payments/payouts), Google LLC (Sign-In, Play Services Geocoder, Maps navigation links, DNS-over-HTTPS), Firebase Cloud Messaging (push notifications), Twilio SendGrid (OTP/transactional email), Railway & Netlify (cloud infrastructure), and OpenStreetMap Nominatim, Komoot Photon, OSRM, and Cloudflare DoH (location search, routing estimation & network resilience). Workmate4u is not liable for outages, delays, or data handling performed under those third parties\' own terms.',
            ),

            _section(
              '13. Disclaimers ("AS IS") & Limitation of Liability',
              'THE PLATFORM IS PROVIDED ON AN "AS-IS" AND "AS-AVAILABLE" BASIS WITHOUT WARRANTIES OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING ACCURACY OF LOCATION/DISTANCE ESTIMATES, CONTINUOUS AVAILABILITY, OR USER CONDUCT.\n\nTO THE MAXIMUM EXTENT PERMITTED BY INDIAN LAW, WORKMATE4U SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, EXEMPLARY, OR PUNITIVE DAMAGES, LOSS OF PROFITS, DATA LOSS, PERSONAL INJURY, OR PROPERTY DAMAGE. WORKMATE4U\'S MAXIMUM AGGREGATE LIABILITY FOR ALL CLAIMS ARISING OUT OF OR RELATING TO THE PLATFORM SHALL NOT EXCEED THE TOTAL PLATFORM FEES ACTUALLY RETAINED BY WORKMATE4U FROM YOU IN THE THREE (3) MONTHS PRECEDING THE CLAIM, OR INR 5,000 (RUPEES FIVE THOUSAND), WHICHEVER IS LOWER.',
            ),

            _section(
              '14. Comprehensive Indemnification',
              'You agree to defend, indemnify, and hold harmless Workmate4u and its owners, officers, employees, and agents from and against all claims, damages, liabilities, penalties, fines, criminal defense costs, and reasonable legal fees arising out of or relating to: (a) your breach of these Terms or any law; (b) misrepresentation of your age (<18), identity, KYC documents, or engagement/subcontracting of any minor or adolescent; (c) personal injury, death, road accident, property damage, theft, or third-party claims during any task; (d) failure to hold valid licences/insurance/permits; (e) IP infringement or unpaid pass-through costs/taxes; or (f) fraudulent chargebacks or off-platform dealings.',
            ),

            _section(
              '15. Grievance Officer (IT Rules, 2021) & Content Takedown',
              'Pursuant to Rule 3(2) of the Information Technology (Intermediary Guidelines and Digital Media Ethics Code) Rules, 2021, grievances regarding unlawful content, safety incidents, impersonation, or account action may be sent to our Grievance Cell. Complaints are acknowledged within 24 hours and addressed within 15 days (or 72 hours for urgent statutory/non-consensual media takedowns):',
              bullets: [
                'Grievance Officer: Workmate4u Grievance Cell',
                'Email: info@workmate4u.com',
                'Website: https://workmate4u.com',
              ],
            ),

            _section('16. Governing Law, Arbitration & General Provisions', null, subsections: [
              const _SubSection(
                '16.1 Governing Law & Binding Arbitration',
                'These Terms are governed by the laws of India. Parties shall first attempt good-faith amicable resolution for 30 days by writing to info@workmate4u.com. Any unresolved dispute shall be referred to binding arbitration by a sole arbitrator under the Arbitration and Conciliation Act, 1996 (as amended), seated in New Delhi, India, conducted in English. Subject to arbitration, the competent courts at New Delhi shall have exclusive jurisdiction.',
              ),
              const _SubSection(
                '16.2 Force Majeure, Severability, Waiver & Survival',
                'Workmate4u is excused from performance delays caused by events beyond reasonable control (acts of God, telecom/cloud outages, strikes, pandemics, bank/RBI/payment-gateway downtime, or government orders). If any provision is held invalid, remaining clauses stay fully enforceable. Failure to enforce any right is not a waiver. Sections 2 (18+ & Anti-Child-Labour), 4, 6.4, 8, 9, 11, 13, 14, and 16 survive account termination. These Terms and the Privacy Policy form the entire agreement.',
              ),
              const _SubSection(
                '16.3 Changes to These Terms',
                'Material updates will be notified in-app at least 7 days before taking effect (or immediately where required by law or safety). Continued use after the effective date constitutes binding acceptance.',
              ),
            ]),

            _section('17. Contact Information', null, bullets: [
              'Operator: Workmate4u, India',
              'Support & Legal Email: info@workmate4u.com',
              'Website: https://workmate4u.com',
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
                'Last Updated: $kLegalEffectiveDate\nEffective Date: $kLegalEffectiveDate\nTerms Version: $kTermsVersion',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF4338CA),
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
                  color: Colors.white70,
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
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: const Border(
                  left: BorderSide(color: Color(0xFF6366F1), width: 3)),
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
          color:
              isWarning ? const Color(0xFFFEF3C7) : const Color(0xFFEEF2FF),
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
