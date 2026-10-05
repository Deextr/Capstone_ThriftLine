import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/data/seller_listings_refresh.dart';

void main() {
  test('notify invokes registered seller listener', () {
    var calls = 0;
    void onRefresh() => calls++;
    SellerListingsRefresh.addListener('seller-a', onRefresh);
    SellerListingsRefresh.notify('seller-a');
    expect(calls, 1);
    SellerListingsRefresh.removeListener('seller-a', onRefresh);
  });

  test('notify does not invoke other sellers listeners', () {
    var calls = 0;
    void onRefresh() => calls++;
    SellerListingsRefresh.addListener('seller-a', onRefresh);
    SellerListingsRefresh.notify('seller-b');
    expect(calls, 0);
    SellerListingsRefresh.removeListener('seller-a', onRefresh);
  });
}
