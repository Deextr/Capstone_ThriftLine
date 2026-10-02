import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/buyer/domain/looking_for_lifecycle.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/looking_for_model.dart';
import 'package:thriftline/widgets/looking_for_card.dart';

void main() {
  final created = DateTime.parse('2026-10-02T10:00:00+08:00');
  final expires = lookingForExpiresAt(created);
  final before = DateTime.parse('2026-10-05T09:59:00+08:00');
  final after = DateTime.parse('2026-10-05T10:00:00+08:00');

  LookingForModel request({
    required DateTime serverNow,
    DateTime? moderationRemovedAt,
    DateTime? ownerDeletedAt,
    String status = 'open',
    DateTime? expiresAt,
  }) {
    return LookingForModel(
      id: 'post-1',
      buyerId: 'buyer-1',
      buyerName: 'Amina Cruz',
      buyerAvatar: '',
      title: 'Looking for white Lacoste shirt',
      description: 'Size M, good condition.',
      category: ProductCategory.tops,
      budgetMin: 200,
      budgetMax: 800,
      location: 'Davao',
      createdAt: created,
      expiresAt: expiresAt ?? expires,
      moderationRemovedAt: moderationRemovedAt,
      ownerDeletedAt: ownerDeletedAt,
      observedAt: serverNow,
      status: switch (status) {
        'fulfilled' => LookingForStatus.fulfilled,
        'closed' => LookingForStatus.closed,
        _ => LookingForStatus.active,
      },
    );
  }

  test('a new request expires exactly three days later', () {
    expect(
      expires.toUtc(),
      DateTime.parse('2026-10-05T10:00:00+08:00').toUtc(),
    );
  });

  test('a request is still active one minute before expiry', () {
    final post = request(serverNow: before);
    expect(post.lifecycle, LookingForLifecycle.active);
    expect(post.showInBrowse, isTrue);
    expect(post.showInMyActive, isTrue);
    expect(post.showInInactive, isFalse);
    expect(post.lifecycleLabel, 'Expires in 1 minute');
  });

  test('a request is expired at the server expiry instant', () {
    final post = request(serverNow: after);
    expect(post.lifecycle, LookingForLifecycle.expired);
    expect(post.showInBrowse, isFalse);
    expect(post.showInMyActive, isFalse);
    expect(post.showInInactive, isTrue);
    expect(post.lifecycleLabel, 'Expired');
    expect(post.canRepost, isTrue);
    expect(post.canDelete, isTrue);
  });

  test('expiration is not a strike', () {
    expect(lookingForExpirationCountsAsStrike(), isFalse);
  });

  test('an active request cannot be reposted', () {
    expect(request(serverNow: before).canRepost, isFalse);
  });

  test('a moderation removal is not an expiration and cannot be reposted', () {
    final post = request(serverNow: after, moderationRemovedAt: after);
    expect(post.lifecycle, LookingForLifecycle.removed);
    expect(post.lifecycleLabel, 'Removed');
    expect(post.showInBrowse, isFalse);
    expect(post.showInInactive, isTrue);
    expect(post.canRepost, isFalse);
    expect(post.canDelete, isFalse);
  });

  test('a deleted request leaves the owner lists', () {
    final post = request(serverNow: after, ownerDeletedAt: after);
    expect(post.lifecycle, LookingForLifecycle.deleted);
    expect(post.showInInactive, isFalse);
    expect(post.showInBrowse, isFalse);
  });

  test('repost starts a fresh three-day window from the repost time', () {
    final repostedAt = DateTime.parse('2026-10-05T15:00:00+08:00');
    expect(
      lookingForExpiresAt(repostedAt).toUtc(),
      DateTime.parse('2026-10-08T15:00:00+08:00').toUtc(),
    );
  });

  test('five posts in 24 hours are allowed and a sixth is not', () {
    final now = DateTime.utc(2026, 10, 2, 12);
    final four = List.generate(
      4,
      (index) => now.subtract(Duration(hours: index + 1)),
    );
    expect(lookingForRateLimitAllows(four, serverNow: now), isTrue);
    final five = [...four, now.subtract(const Duration(minutes: 2))];
    expect(lookingForRateLimitAllows(five, serverNow: now), isFalse);
  });

  test('deleting posts does not remove them from the rate-limit ledger', () {
    final now = DateTime.utc(2026, 10, 2, 12);
    final created = List.generate(
      5,
      (index) => now.subtract(Duration(minutes: 10 + index)),
    );
    expect(lookingForPostsInWindow(created, serverNow: now), 5);
    expect(lookingForRateLimitAllows(created, serverNow: now), isFalse);
  });

  test('a repost counts as a post in the rolling window', () {
    final now = DateTime.utc(2026, 10, 2, 12);
    final activity = [
      now.subtract(const Duration(hours: 2)),
      now.subtract(const Duration(hours: 1)),
      now,
    ];
    expect(lookingForPostsInWindow(activity, serverNow: now), 3);
  });

  test('posts older than 24 hours fall out of the window', () {
    final now = DateTime.utc(2026, 10, 3, 12);
    final activity = [now.subtract(const Duration(hours: 25))];
    expect(lookingForRateLimitAllows(activity, serverNow: now), isTrue);
  });

  test('cooldown blocks a second post inside 45 seconds', () {
    final now = DateTime.utc(2026, 10, 2, 12);
    expect(
      lookingForCooldownClear(
        lastActivityAt: now.subtract(const Duration(seconds: 20)),
        serverNow: now,
      ),
      isFalse,
    );
    expect(
      lookingForCooldownClear(
        lastActivityAt: now.subtract(const Duration(seconds: 45)),
        serverNow: now,
      ),
      isTrue,
    );
  });

  test('exact and normalized titles match as duplicates', () {
    expect(
      lookingForTextsMatch(
        'Looking for white Lacoste shirt',
        'Looking for white Lacoste shirt',
      ),
      isTrue,
    );
    expect(
      lookingForTextsMatch(
        'Looking for White Lacoste Shirt!',
        ' looking for white lacoste shirt ',
      ),
      isTrue,
    );
  });

  test('near-duplicate requests match and unrelated requests do not', () {
    expect(
      lookingForTextsMatch(
        'Looking for white Lacoste polo',
        'Need a white Lacoste polo shirt',
      ),
      isTrue,
    );
    expect(
      lookingForTextsMatch(
        'Looking for white Lacoste shirt',
        'Looking for black Nike running shoes',
      ),
      isFalse,
    );
  });

  test('only confirmed offenses become strikes', () {
    expect(lookingForStrikeConsequence(1), LookingForStrikeConsequence.warning);
    expect(
      lookingForStrikeConsequence(2),
      LookingForStrikeConsequence.restriction,
    );
    expect(
      lookingForStrikeConsequence(3),
      LookingForStrikeConsequence.permanentDisable,
    );
  });

  test('other reports need a short explanation', () {
    expect(
      lookingForReportDetailsError(reason: 'other', details: 'bad'),
      isNotNull,
    );
    expect(
      lookingForReportDetailsError(
        reason: 'other',
        details: 'This is a troll post.',
      ),
      isNull,
    );
    expect(lookingForReportDetailsError(reason: 'spam', details: ''), isNull);
  });

  test('human expiration copy stays coarse', () {
    final now = DateTime.parse('2026-10-02T10:00:00+08:00');
    expect(
      lookingForExpirationLabel(
        expiresAt: now.add(const Duration(hours: 3)),
        serverNow: now,
      ),
      'Expires in 3 hours',
    );
    expect(
      lookingForExpirationLabel(
        expiresAt: now.add(const Duration(hours: 30)),
        serverNow: now,
      ),
      'Expires tomorrow',
    );
    expect(
      lookingForExpirationLabel(
        expiresAt: now.add(const Duration(days: 2)),
        serverNow: now,
      ),
      'Expires in 2 days',
    );
  });

  testWidgets('a long request title does not overflow a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LookingForCard(
            post: request(serverNow: before).copyWith(
              title:
                  'Looking for a white Lacoste shirt from a Davao seller this week',
            ),
            showReport: true,
            showShare: true,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Report request'), findsNothing);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Report request'), findsOneWidget);
  });

  testWidgets('inactive actions stay on a wide phone', (tester) async {
    tester.view.physicalSize = const Size(840, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LookingForCard(
            post: request(serverNow: after),
            showOwnerActions: true,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Expired'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Repost'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });
}
