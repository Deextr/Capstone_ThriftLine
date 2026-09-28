import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/enums.dart';
import '../../../models/product_model.dart';
import '../../../providers/auth_provider.dart';
import '../../buyer/data/catalog_product_query.dart';

class MyShopController extends ChangeNotifier {
  MyShopController({
    required SupabaseService supabase,
    required AuthProvider auth,
  }) : _supabase = supabase,
       _auth = auth {
    load();
  }

  final SupabaseService _supabase;
  final AuthProvider _auth;

  List<ProductModel> _products = [];
  int _followerCount = 0;
  int _followingCount = 0;
  String? _shopBio;
  bool _isLoading = false;
  String? _errorMessage;

  List<ProductModel> get products => _products;
  List<ProductModel> get previewProducts => _products.take(6).toList();
  int get followerCount => _followerCount;
  int get followingCount => _followingCount;
  String? get shopBio => _shopBio;
  int get soldCount =>
      _products.where((p) => p.status == ProductStatus.sold).length;
  int get activeCount =>
      _products.where((p) => p.status == ProductStatus.active).length;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> load() async {
    final userId = _auth.user?.id;
    if (userId == null) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      try {
        final profile = await _supabase.client
            .from('seller_profiles')
            .select()
            .eq('seller_id', userId)
            .maybeSingle();
        final bio = profile?['shop_bio'] as String?;
        _shopBio = (bio != null && bio.trim().isNotEmpty) ? bio.trim() : null;
      } catch (e) {
        debugPrint('MyShopController: seller_profiles error ($e)');
      }

      try {
        final followers = await _supabase.client
            .from('follows')
            .select('follower_id')
            .eq('following_id', userId);
        _followerCount = (followers as List).length;
      } catch (e) {
        debugPrint('MyShopController: follower count error ($e)');
      }

      try {
        final following = await _supabase.client
            .from('follows')
            .select('following_id')
            .eq('follower_id', userId);
        _followingCount = (following as List).length;
      } catch (e) {
        debugPrint('MyShopController: following count error ($e)');
      }

      final sellerProfiles = await fetchSellerProfilesMap(
        _supabase.client,
        extraSellerIds: [userId],
        includeApproved: false,
      );
      final rows = await runProductCatalogSelect((select) async {
        return await _supabase.client
            .from('products')
            .select(select)
            .eq('seller_id', userId)
            .inFilter('status', ['active', 'sold'])
            .order('created_at', ascending: false);
      });

      _products = hydrateCatalogProducts(rows as List<dynamic>, sellerProfiles);
    } catch (e) {
      debugPrint('MyShopController.load error: $e');
      _errorMessage = 'Unable to load your shop.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
