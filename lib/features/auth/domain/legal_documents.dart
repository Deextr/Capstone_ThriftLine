/// Terms and Conditions / Privacy Policy content and the consent record that
/// is stored against a user account when they accept them.
library;

/// Which legal document to display.
enum LegalDocumentType { terms, privacy }

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
  static const String version = '2026.08.1';
  static const String lastUpdated = 'August 2026';

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
            'When you register, we send a confirmation link to the address you '
            'provided so we can verify that it belongs to you. The link is '
            'generated and validated by our authentication provider and can '
            'only be used once.',
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

  static LegalDocument byType(LegalDocumentType type) =>
      switch (type) {
        LegalDocumentType.terms => terms,
        LegalDocumentType.privacy => privacy,
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
