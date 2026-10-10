import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/admin/data/admin_audit_log_models.dart';

AdminAuditLogRow _row({
  String? targetType,
  String? targetId,
  String summary = '',
  String eventType = '',
  Map<String, dynamic> details = const {},
}) {
  return AdminAuditLogRow(
    logId: 'log-1',
    createdAt: DateTime.utc(2026, 1, 1),
    category: 'account_management',
    eventType: eventType,
    status: 'success',
    summary: summary,
    targetType: targetType,
    targetId: targetId,
    details: details,
  );
}

void main() {
  test(
    'verification target shows friendly label and compact ref, not full uuid',
    () {
      const id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
      final row = _row(
        targetType: 'verification',
        targetId: id,
        eventType: 'seller_verification_approved',
        summary: 'Approved seller verification',
      );

      expect(row.targetDisplayPrimary, 'Seller verification');
      expect(row.targetDisplaySecondary, 'Ref 34567890');
      expect(row.targetDisplayPrimary.contains('-'), isFalse);
    },
  );

  test('disabled user target prefers name from summary', () {
    final row = _row(
      targetType: 'user',
      targetId: '11111111-2222-3333-4444-555555555555',
      eventType: 'marketplace_account_disabled',
      summary: 'Disabled marketplace account Maya Cruz',
    );

    expect(row.targetDisplayPrimary, 'Maya Cruz');
    expect(row.targetDisplaySecondary, 'Ref 55555555');
  });

  test('performed by shows role on primary line and name below', () {
    final row = AdminAuditLogRow(
      logId: 'log-2',
      createdAt: DateTime.utc(2026, 1, 1),
      category: 'account_management',
      eventType: 'admin_invited',
      status: 'success',
      summary: 'Invited an administrator',
      actorUserId: 'actor-1',
      actorFullName: 'Jordan Lee',
      actorRole: 'super_admin',
    );

    expect(row.actorRoleDisplayLine, 'Superadmin');
    expect(row.actorNameDisplayLine, 'Jordan Lee');
  });

  test('admin invitation target uses invite email from details', () {
    final row = _row(
      targetType: 'admin_invitation',
      targetId: '99999999-8888-7777-6666-555555555555',
      eventType: 'admin_invited',
      summary: 'Invited an administrator',
      details: const {'email': 'ops@thriftline.test'},
    );

    expect(row.targetDisplayPrimary, 'ops@thriftline.test');
    expect(row.targetDisplaySecondary, 'Ref 55555555');
  });
}
