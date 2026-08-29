import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/data/davao_barangay_service.dart';
import 'package:thriftline/features/seller/domain/davao_barangay.dart';
import 'package:thriftline/features/seller/domain/seller_address_draft.dart';

void main() {
  group('DavaoBarangay.fromApiList', () {
    test('keeps only Davao City barangays and drops other cities', () {
      final list = DavaoBarangay.fromApiList([
        {
          'code': '112402002',
          'name': 'Agdao',
          'cityCode': '112402000',
        },
        {
          'code': '137404001',
          'name': 'Ermita',
          'cityCode': '137404000',
        },
        {
          'code': '112403001',
          'name': 'Aplaya',
          'cityCode': '112403000',
        },
      ]);

      expect(list, hasLength(1));
      expect(list.single.name, 'Agdao');
      expect(list.single.isDavaoCity, isTrue);
    });

    test('deduplicates by code and by name', () {
      final list = DavaoBarangay.fromApiList([
        {'code': '1', 'name': 'Sasa', 'cityCode': '112402000'},
        {'code': '1', 'name': 'Sasa', 'cityCode': '112402000'},
        {'code': '2', 'name': 'Sasa', 'cityCode': '112402000'},
      ]);
      expect(list, hasLength(1));
    });

    test('treats a non-list payload as invalid', () {
      expect(
        () => DavaoBarangay.fromApiList({'name': 'Davao City'}),
        throwsFormatException,
      );
    });

    test('returns empty when the array has no Davao City rows', () {
      expect(
        DavaoBarangay.fromApiList([
          {'code': 'x', 'name': 'Poblacion', 'cityCode': '137404000'},
        ]),
        isEmpty,
      );
    });
  });

  group('DavaoBarangayService', () {
    test('rejects an empty filtered payload', () async {
      final service = DavaoBarangayService(
        fetch: (_) async =>
            '[{"code":"1","name":"Ermita","cityCode":"137404000"}]',
      );
      expect(
        () => service.load(),
        throwsA(
          isA<DavaoBarangayException>().having(
            (e) => e.kind,
            'kind',
            DavaoBarangayErrorKind.empty,
          ),
        ),
      );
    });

    test('rejects invalid JSON', () async {
      final service = DavaoBarangayService(fetch: (_) async => 'not-json');
      expect(
        () => service.load(),
        throwsA(
          isA<DavaoBarangayException>().having(
            (e) => e.kind,
            'kind',
            DavaoBarangayErrorKind.invalid,
          ),
        ),
      );
    });

    test('caches a successful Davao City payload', () async {
      var calls = 0;
      final service = DavaoBarangayService(
        fetch: (_) async {
          calls++;
          return '[{"code":"112402002","name":"Agdao","cityCode":"112402000"}]';
        },
      );
      final first = await service.load();
      final second = await service.load();
      expect(first.single.name, 'Agdao');
      expect(second, first);
      expect(calls, 1);
    });
  });

  group('SellerAddressDraft', () {
    final agdao = DavaoBarangay(
      code: '112402002',
      name: 'Agdao',
      cityCode: DavaoBarangay.cityCodePsgc9,
    );

    test('requires store name, Davao barangay, and address line 1', () {
      expect(
        SellerAddressDraft.validate(
          storeName: '',
          barangay: agdao,
          allowedBarangays: [agdao],
          addressLine1: '123 Street',
        ),
        'Please enter a store name.',
      );
      expect(
        SellerAddressDraft.validate(
          storeName: 'Shop',
          barangay: null,
          allowedBarangays: [agdao],
          addressLine1: '123 Street',
        ),
        'Please select a Davao City barangay.',
      );
      expect(
        SellerAddressDraft.validate(
          storeName: 'Shop',
          barangay: agdao,
          allowedBarangays: [agdao],
          addressLine1: '  ',
        ),
        'Please enter Address Line 1.',
      );
      expect(
        SellerAddressDraft.validate(
          storeName: 'Shop',
          barangay: agdao,
          allowedBarangays: [agdao],
          addressLine1: '123 Street',
        ),
        isNull,
      );
    });

    test('rejects a barangay that is not in the loaded Davao list', () {
      final outsider = DavaoBarangay(
        code: '999',
        name: 'Ermita',
        cityCode: '137404000',
      );
      expect(
        SellerAddressDraft.validate(
          storeName: 'Shop',
          barangay: outsider,
          allowedBarangays: [agdao],
          addressLine1: '123 Street',
        ),
        'Please select a Davao City barangay.',
      );
    });

    test('composes address line 2 only when present', () {
      expect(
        const SellerAddressDraft(
          storeName: 'Shop',
          barangay: null,
          addressLine1: '123 Street',
        ).composedShopAddress,
        '123 Street',
      );
      expect(
        const SellerAddressDraft(
          storeName: 'Shop',
          barangay: null,
          addressLine1: '123 Street',
          addressLine2: 'Unit 4',
        ).composedShopAddress,
        '123 Street, Unit 4',
      );
    });
  });
}
