import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thriftline/core/services/shared_preferences_service.dart';
import 'package:thriftline/core/utils/validators.dart';
import 'package:thriftline/features/auth/domain/account_mode.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/seller_profile.dart';
import 'package:thriftline/models/user_model.dart';
import 'package:thriftline/widgets/thrift_widgets.dart';

import '../support/qa_reporter.dart';

/// Profile edit harness simulating the user profile update flow.
class _ProfileEditHarness extends StatefulWidget {
  const _ProfileEditHarness({
    required this.user,
    required this.onSave,
  });

  final UserModel user;
  final void Function({
    required String name,
    required String bio,
    required String location,
  }) onSave;

  @override
  State<_ProfileEditHarness> createState() => _ProfileEditHarnessState();
}

class _ProfileEditHarnessState extends State<_ProfileEditHarness> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  late final TextEditingController _locationController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.name);
    _bioController = TextEditingController(text: widget.user.bio ?? '');
    _locationController =
        TextEditingController(text: widget.user.location ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      widget.onSave(
        name: Validators.normalizeFullName(_nameController.text),
        bio: _bioController.text.trim(),
        location: _locationController.text.trim(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ThriftTextField(
                key: const Key('profile-name-field'),
                label: 'Full Name',
                controller: _nameController,
                validator: Validators.name,
              ),
              const SizedBox(height: 12),
              ThriftTextField(
                key: const Key('profile-bio-field'),
                label: 'Bio',
                controller: _bioController,
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              ThriftTextField(
                key: const Key('profile-location-field'),
                label: 'Location',
                controller: _locationController,
              ),
              const SizedBox(height: 24),
              ThriftButton(
                key: const Key('profile-save-button'),
                label: 'Save Profile',
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Finder _profileInput(String key) => find.descendant(
      of: find.byKey(Key(key)),
      matching: find.byType(TextFormField),
    );

void profileAccountIntegrationTests() {
  qaGroup('Profile & Account Mode Integration Flow', () {
    qaIntegrationTest(
        'profile edit validates name and saves normalized user data', (
      tester,
    ) async {
      final user = UserModel.fromJson({
        'id': 'user-qa-1',
        'name': 'Dexter Ramos',
        'username': 'dexter_r',
        'email': 'dexter@thriftline.ph',
        'phone': '09171234567',
        'bio': 'Vintage thrift enthusiast',
        'location': 'Davao City',
        'role': 'buyer',
        'createdAt': '2026-01-15T00:00:00.000Z',
      });

      String? savedName;
      String? savedBio;
      String? savedLocation;

      await tester.pumpWidget(
        MaterialApp(
          home: _ProfileEditHarness(
            user: user,
            onSave: ({required name, required bio, required location}) {
              savedName = name;
              savedBio = bio;
              savedLocation = location;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify initial values are populated
      expect(find.text('Dexter Ramos'), findsOneWidget);

      // 2. Clear name and try to save
      await tester.enterText(_profileInput('profile-name-field'), '');
      await tester.ensureVisible(find.byKey(const Key('profile-save-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-save-button')));
      await tester.pumpAndSettle();

      expect(find.text(Validators.fullNameRequiredMessage), findsOneWidget);
      expect(savedName, isNull);

      // 3. Enter messy name with extra whitespace
      await tester.enterText(
          _profileInput('profile-name-field'), '  Maria  Clara  Santos  ');
      await tester.enterText(
          _profileInput('profile-bio-field'), 'Thrift lover from the south!');
      await tester.enterText(
          _profileInput('profile-location-field'), 'Tagum City');

      await tester.ensureVisible(find.byKey(const Key('profile-save-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-save-button')));
      await tester.pumpAndSettle();

      expect(savedName, 'Maria Clara Santos'); // normalized
      expect(savedBio, 'Thrift lover from the south!');
      expect(savedLocation, 'Tagum City');
    });

    qaIntegrationTest(
        'UserModel.fromJson parses all fields and supports copyWith', (
      tester,
    ) async {
      final user = UserModel.fromJson({
        'user_id': 'user-parse-001',
        'full_name': 'Dexter Ramos',
        'username': 'dexter_r',
        'email': 'dexter@thriftline.ph',
        'phone_number': '09171234567',
        'avatar': 'https://example.com/avatar.jpg',
        'bio': 'Vintage lover',
        'location': 'Davao City',
        'role': 'seller',
        'created_at': '2026-01-15T00:00:00.000Z',
        'isVerified': true,
      });

      expect(user.id, 'user-parse-001');
      expect(user.name, 'Dexter Ramos');
      expect(user.username, 'dexter_r');
      expect(user.email, 'dexter@thriftline.ph');
      expect(user.phone, '09171234567');
      expect(user.role, UserRole.seller);
      expect(user.isVerified, isTrue);

      // copyWith preserves unchanged fields
      final updated = user.copyWith(bio: 'Updated bio', location: 'Manila');
      expect(updated.id, user.id);
      expect(updated.name, user.name);
      expect(updated.bio, 'Updated bio');
      expect(updated.location, 'Manila');

      // Equality by ID
      final sameUser = user.copyWith(name: 'Different Name');
      expect(user == sameUser, isTrue);
    });

    qaIntegrationTest(
        'SellerProfile.fromSupabase parses shop data with trust and stats', (
      tester,
    ) async {
      final profile = SellerProfile.fromSupabase(
        {
          'seller_id': 'seller-profile-001',
          'shop_name': 'Ukay Thrift Davao',
          'shop_bio': 'Curated vintage finds from Davao',
          'total_sales': 142,
          'follower_count': 320,
          'following_count': 15,
          'city': 'Davao City',
          'is_approved': true,
          'created_at': '2025-06-01T00:00:00.000Z',
        },
        userRow: {
          'user_id': 'seller-profile-001',
          'username': 'ukay_thrift',
          'full_name': 'Maria Santos',
          'avatar': 'https://example.com/shop-avatar.jpg',
          'rating_average': 4.8,
          'rating_count': 96,
          'trust_score': 92,
          'trust_level': 'highly_trusted',
          'email': 'ukay@thriftline.ph',
          'phone_number': '09171234567',
        },
        activeProductCount: 35,
      );

      expect(profile.sellerId, 'seller-profile-001');
      expect(profile.shopName, 'Ukay Thrift Davao');
      expect(profile.ownerName, 'Maria Santos');
      expect(profile.username, 'ukay_thrift');
      expect(profile.rating, 4.8);
      expect(profile.ratingCount, 96);
      expect(profile.sales, 142);
      expect(profile.itemCount, 35);
      expect(profile.followerCount, 320);
      expect(profile.trustScore, 92);
      expect(profile.isVerified, isTrue);
      expect(profile.location, 'Davao City');
      expect(profile.shopBio, 'Curated vintage finds from Davao');
      expect(profile.email, 'ukay@thriftline.ph');

      // Shop name fallback when empty
      final noShopName = SellerProfile.fromSupabase(
        {'shop_name': '', 'total_sales': 0},
        userRow: {
          'username': 'new_seller',
          'full_name': 'New Seller Person',
        },
      );
      expect(noShopName.shopName, 'New Seller Person'); // falls back to owner
    });

    qaIntegrationTest(
        'account mode resolution follows seller-access and admin rules', (
      tester,
    ) async {
      // Buyer without seller access always gets buyer mode
      expect(
        resolveAccountMode(
          hasSellerAccess: false,
          isAdmin: false,
          restoreFromPrefs: false,
        ),
        AccountMode.buyer,
      );

      // Admin always gets buyer mode (admin surfaces shown separately)
      expect(
        resolveAccountMode(
          hasSellerAccess: true,
          isAdmin: true,
          restoreFromPrefs: false,
        ),
        AccountMode.buyer,
      );

      // Seller restoring from prefs with 'seller' saved → seller
      expect(
        resolveAccountMode(
          hasSellerAccess: true,
          isAdmin: false,
          savedMode: 'seller',
          restoreFromPrefs: true,
        ),
        AccountMode.seller,
      );

      // Seller restoring from prefs with 'buyer' saved → buyer
      expect(
        resolveAccountMode(
          hasSellerAccess: true,
          isAdmin: false,
          savedMode: 'buyer',
          restoreFromPrefs: true,
        ),
        AccountMode.buyer,
      );

      // First time seller (no saved mode) defaults to seller
      expect(
        resolveAccountMode(
          hasSellerAccess: true,
          isAdmin: false,
          savedMode: null,
          restoreFromPrefs: true,
        ),
        AccountMode.seller,
      );

      // Seller access helper
      expect(
        authHasSellerAccess(isVerified: true, roleIsSeller: false),
        isTrue,
      );
      expect(
        authHasSellerAccess(isVerified: false, roleIsSeller: true),
        isTrue,
      );
      expect(
        authHasSellerAccess(isVerified: false, roleIsSeller: false),
        isFalse,
      );

      // Account switching
      expect(
        authCanSwitchAccounts(hasSellerAccess: true, isAdmin: false),
        isTrue,
      );
      expect(
        authCanSwitchAccounts(hasSellerAccess: true, isAdmin: true),
        isFalse,
      );
      expect(
        authCanSwitchAccounts(hasSellerAccess: false, isAdmin: false),
        isFalse,
      );

      // Edit own shop only in seller workspace
      expect(
        canEditOwnPublicShop(isOwnShop: true, isSellerWorkspace: true),
        isTrue,
      );
      expect(
        canEditOwnPublicShop(isOwnShop: true, isSellerWorkspace: false),
        isFalse,
      );
      expect(
        canEditOwnPublicShop(isOwnShop: false, isSellerWorkspace: true),
        isFalse,
      );
    });

    qaIntegrationTest(
        'account mode persists and restores via SharedPreferences', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferencesService.init();

      // Save seller account mode
      await prefs.setActiveAccount(userId: 'user-qa-1', mode: 'seller');
      expect(prefs.activeAccountFor('user-qa-1'), 'seller');

      // Switch to buyer
      await prefs.setActiveAccount(userId: 'user-qa-1', mode: 'buyer');
      expect(prefs.activeAccountFor('user-qa-1'), 'buyer');

      // Different user has no saved mode
      expect(prefs.activeAccountFor('user-other-99'), isNull);

      // Session data persists across preferences
      await prefs.setLoggedIn(true);
      await prefs.setUserId('user-qa-1');
      await prefs.setDisplayName('Dexter Ramos');
      await prefs.setUserRole('seller');

      expect(prefs.isLoggedIn, isTrue);
      expect(prefs.userId, 'user-qa-1');
      expect(prefs.displayName, 'Dexter Ramos');
      expect(prefs.userRole, 'seller');
    });
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(QaReporter.printFinalReport);

  qaSection(QaTestType.integration, () {
    profileAccountIntegrationTests();
  });
}
