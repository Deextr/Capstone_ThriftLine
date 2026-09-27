/// Terms and Conditions / Privacy Policy content and the consent record that
/// is stored against a user account when they accept them.
library;

/// Which legal document to display.
enum LegalDocumentType { terms, privacy, about, faq }

/// A titled block of legal copy.
class LegalSection {
  const LegalSection({required this.heading, required this.body});

  final String heading;
  final String body;
}

/// A complete legal document rendered by `LegalDocumentScreen`.
class LegalDocument {
  const LegalDocument({
    required this.type,
    required this.title,
    required this.summary,
    required this.sections,
  });

  final LegalDocumentType type;
  final String title;
  final String summary;
  final List<LegalSection> sections;
}

/// Static source of truth for ThriftLine's legal copy.
///
/// Bump [version] whenever the wording changes materially so that acceptance
/// records remain auditable.
abstract final class LegalDocuments {
  static const String version = '2026.09.1';
  static const String lastUpdated = 'September 2026';

  static const LegalDocument terms = LegalDocument(
    type: LegalDocumentType.terms,
    title: 'Terms and Conditions',
    summary:
        'The rules that apply when you buy, sell, or browse on ThriftLine.',
    sections: [
      LegalSection(
        heading: '1. Accepting these Terms',
        body:
            'By creating a ThriftLine account or signing in, you confirm that '
            'you are at least 18 years old and that you agree to be bound by '
            'these Terms and Conditions. If you do not agree, you may not use '
            'the application.',
      ),
      LegalSection(
        heading: '2. Your Account',
        body:
            'You are responsible for keeping your login credentials '
            'confidential and for all activity that happens under your '
            'account. Notify us immediately if you believe someone else has '
            'accessed your account.',
      ),
      LegalSection(
        heading: '3. Buying on ThriftLine',
        body:
            'Listings are created by independent sellers. ThriftLine provides '
            'the marketplace, escrow handling, and dispute support, but it '
            'does not own the items being sold. Review item photos, condition '
            'labels, and seller trust scores before committing to a purchase.',
      ),
      LegalSection(
        heading: '4. Selling on ThriftLine',
        body:
            'Sellers must provide accurate descriptions, original photographs '
            'of the actual item, and must dispatch orders promptly. '
            'Counterfeit, mislabeled, prohibited, or unsafe items are not '
            'permitted and will result in listing removal and possible '
            'account suspension.',
      ),
      LegalSection(
        heading: '5. Payments and Escrow',
        body:
            'Payments made through ThriftLine may be held in escrow until the '
            'buyer confirms delivery. Platform fees are shown before you '
            'confirm an order. Refunds are handled according to the outcome of '
            'our dispute resolution process.',
      ),
      LegalSection(
        heading: '6. Prohibited Conduct',
        body:
            'You may not harass other members, manipulate ratings or trust '
            'scores, attempt to move transactions off-platform to avoid buyer '
            'protection, scrape the service, or interfere with its security.',
      ),
      LegalSection(
        heading: '7. Suspension and Termination',
        body:
            'We may suspend or terminate accounts that violate these Terms, '
            'that are associated with fraudulent activity, or that place other '
            'members at risk. You may close your account at any time from the '
            'app settings.',
      ),
      LegalSection(
        heading: '8. Changes to these Terms',
        body:
            'We may update these Terms as the service evolves. When we make '
            'material changes we will ask you to review and accept the updated '
            'version before you continue using ThriftLine.',
      ),
    ],
  );

  static const LegalDocument privacy = LegalDocument(
    type: LegalDocumentType.privacy,
    title: 'Privacy Policy',
    summary:
        'How ThriftLine collects, uses, and protects your personal data.',
    sections: [
      LegalSection(
        heading: '1. Data Privacy Notice',
        body:
            'ThriftLine processes personal data in line with the Philippine '
            'Data Privacy Act of 2012 (RA 10173). This notice explains what we '
            'collect, why we collect it, and the rights you have over your '
            'information.',
      ),
      LegalSection(
        heading: '2. Information We Collect',
        body:
            'Account data such as your name, email address, and phone number. '
            'Profile data such as your username and avatar. Transaction data '
            'such as orders, delivery addresses, and payment references. '
            'Verification data such as government ID images, if you choose to '
            'apply as a seller.',
      ),
      LegalSection(
        heading: '3. Why We Use Your Data',
        body:
            'To create and secure your account, to verify that you own your '
            'email address, to process orders and deliveries, to calculate '
            'seller trust scores, to investigate reports of fraud or abuse, '
            'and to meet our legal obligations.',
      ),
      LegalSection(
        heading: '4. Email Verification',
        body:
            'When you register with email and password, and each time you sign '
            'in that way, we send a one-time 6-digit code to the address you '
            'provided so we can confirm that you can access that inbox. The '
            'code expires after a few minutes and can be used only once. '
            'Google sign-in does not use this step.',
      ),
      LegalSection(
        heading: '5. Sharing and Disclosure',
        body:
            'We share only the minimum data required to complete a transaction '
            '— for example, a delivery address is shared with the seller '
            'fulfilling your order. We do not sell your personal data. Service '
            'providers who process data on our behalf are bound by '
            'confidentiality obligations.',
      ),
      LegalSection(
        heading: '6. Storage and Security',
        body:
            'Data is stored on managed infrastructure with encryption in '
            'transit and at rest. Access is restricted to authorised personnel. '
            'Passwords are stored only as salted hashes and are never visible '
            'to ThriftLine staff.',
      ),
      LegalSection(
        heading: '7. Your Rights',
        body:
            'You may access, correct, or request deletion of your personal '
            'data, object to certain processing, and withdraw consent. Some '
            'records, such as completed transactions, may be retained where we '
            'are legally required to keep them.',
      ),
      LegalSection(
        heading: '8. Contact',
        body:
            'For any privacy question or to exercise your rights, contact our '
            'Data Protection Officer through the Help Centre in the app.',
      ),
    ],
  );

  static const LegalDocument about = LegalDocument(
    type: LegalDocumentType.about,
    title: 'About ThriftLine',
    summary:
        'ThriftLine is a sustainable peer-to-peer thrift and vintage marketplace connecting mindful buyers and verified sellers across the Philippines.',
    sections: [
      LegalSection(
        heading: '1. Our Mission',
        body:
            'ThriftLine was founded to make sustainable fashion and secondhand shopping accessible, reliable, and secure. We promote a circular economy by helping quality pre-loved clothing, shoes, and vintage treasures find new homes while reducing textile waste.',
      ),
      LegalSection(
        heading: '2. The Marketplace',
        body:
            'Our platform brings together thrifters, vintage curators, and local sellers. With real-time auction bidding, instant "Buy Now" purchases, an item request board for sourcing specific pieces, and direct messaging, ThriftLine makes discovery and trade effortless.',
      ),
      LegalSection(
        heading: '3. Trust and Safety Ecosystem',
        body:
            'We protect our community through government ID seller verification, dynamic trust scores, buyer reviews, payment escrow protection, and a dedicated dispute resolution workflow so you can browse, bid, and buy with total confidence.',
      ),
      LegalSection(
        heading: '4. Academic Capstone Project',
        body:
            'ThriftLine is developed as an academic capstone initiative showcasing modern mobile application architecture, secure authentication, escrow mechanisms, and sustainable peer-to-peer commerce.',
      ),
    ],
  );

  static const LegalDocument faq = LegalDocument(
    type: LegalDocumentType.faq,
    title: 'Frequently Asked Questions',
    summary:
        'Find answers to common questions about buying, bidding, seller verification, payments, escrow protection, and disputes on ThriftLine.',
    sections: [
      LegalSection(
        heading: '1. How do buying and bidding work?',
        body:
            'You can buy items directly at the stated fixed price using "Buy Now" or place real-time bids on auction listings. If you are the highest bidder when an auction concludes, you can immediately proceed to checkout and secure your order.',
      ),
      LegalSection(
        heading: '2. How does the payment escrow protect me?',
        body:
            'When you complete checkout, your payment is held securely in platform escrow. The seller prepares and ships your order, and funds are only disbursed to the seller after you confirm receipt in good order or when delivery is validated.',
      ),
      LegalSection(
        heading: '3. How do I become a verified seller?',
        body:
            'Any registered buyer can apply to become a seller. From your Profile or Seller tab, open seller registration, provide your shop name and payout details (e.g., GCash), and upload a valid government-issued ID. Applications are reviewed promptly by our moderation team.',
      ),
      LegalSection(
        heading: '4. What should I do if an item is fake or not as described?',
        body:
            'If an item you received differs materially from the listing, has undisclosed flaws, or appears counterfeit, navigate to My Orders, select the order, and tap "Report Item" or file a dispute. Provide photos and details, and our Trust & Safety team will review the case to assist with a return or refund.',
      ),
      LegalSection(
        heading: '5. What rules must sellers follow?',
        body:
            'Sellers must provide accurate descriptions, use original photos of the actual item in hand, disclose flaws, ship items promptly within the agreed timeframe, and maintain courteous communication. Counterfeits, mislabeled items, and off-platform payment solicitations are strictly prohibited.',
      ),
      LegalSection(
        heading: '6. How can I contact customer support?',
        body:
            'You can submit inquiries and reports directly through in-app reporting on any order, listing, or user profile. Our Trust & Safety and support team monitors reports daily to assist our community.',
      ),
    ],
  );

  static LegalDocument byType(LegalDocumentType type) =>
      switch (type) {
        LegalDocumentType.terms => terms,
        LegalDocumentType.privacy => privacy,
        LegalDocumentType.about => about,
        LegalDocumentType.faq => faq,
      };
}

/// A user's explicit acceptance of the Terms and Conditions and the Privacy
/// Policy, captured at the moment they tick the consent box.
///
/// Persisted to Supabase auth user metadata so that the acceptance travels with
/// the account and survives reinstalls — no database migration is required.
class LegalConsent {
  const LegalConsent({required this.version, required this.acceptedAt});

  /// Captures consent for the currently published document version.
  factory LegalConsent.now() => LegalConsent(
    version: LegalDocuments.version,
    acceptedAt: DateTime.now().toUtc(),
  );

  final String version;
  final DateTime acceptedAt;

  Map<String, dynamic> toMetadata() => {
    'terms_accepted': true,
    'privacy_policy_accepted': true,
    'legal_version': version,
    'legal_accepted_at': acceptedAt.toIso8601String(),
  };
}
