import '../../../models/enums.dart';
import '../domain/auth_user.dart';
import 'auth_result.dart';

class AuthService {
  static const _invalidCredentialsMessage =
      'Invalid username or password. Please try again.';

  static final Map<String, _Credential> _credentials = {
    'maya_buys': _Credential(
      password: 'buyer123',
      user: AuthUser(
        id: 'buyer_maya',
        username: 'maya_buys',
        name: 'Maya Santos',
        role: UserRole.buyer,
        avatarUrl: 'https://i.pravatar.cc/150?u=maya_buys',
        location: 'Quezon City, Metro Manila',
      ),
    ),
    'james_thrift': _Credential(
      password: 'buyer456',
      user: AuthUser(
        id: 'buyer_james',
        username: 'james_thrift',
        name: 'James Reyes',
        role: UserRole.buyer,
        avatarUrl: 'https://i.pravatar.cc/150?u=james_thrift',
        location: 'Makati City, Metro Manila',
      ),
    ),
    'vintagevibes_ph': _Credential(
      password: 'seller123',
      user: AuthUser(
        id: 'seller_carla',
        username: 'vintagevibes_ph',
        name: 'Carla Mendoza',
        role: UserRole.seller,
        avatarUrl: 'https://i.pravatar.cc/150?u=vintagevibes_ph',
        location: 'Pasig City',
        shopName: 'Vintage Vibes PH',
        rating: 4.8,
        sales: 234,
        isVerified: true,
        bio: 'Philippines Based 🇵🇭 | Curated vintage & Y2K fashion finds ✨ | Haggling is OK',
        lastActive: DateTime.now().subtract(const Duration(hours: 2)),
        trustScore: 95,
      ),
    ),
    'thrift_trendy': _Credential(
      password: 'seller456',
      user: AuthUser(
        id: 'seller_rico',
        username: 'thrift_trendy',
        name: 'Rico Torres',
        role: UserRole.seller,
        avatarUrl: 'https://i.pravatar.cc/150?u=thrift_trendy',
        location: 'Mandaluyong',
        shopName: 'Thrift & Trendy',
        rating: 4.5,
        sales: 156,
        isVerified: true,
        bio: 'Streetwear & Korean fashion 🔥 | Fast shipper 📦 | DM for bundles',
        lastActive: DateTime.now().subtract(const Duration(minutes: 30)),
        trustScore: 78,
      ),
    ),
    'preloved_gems': _Credential(
      password: 'seller789',
      user: AuthUser(
        id: 'seller_anna',
        username: 'preloved_gems',
        name: 'Anna Cruz',
        role: UserRole.seller,
        avatarUrl: 'https://i.pravatar.cc/150?u=preloved_gems',
        location: 'Taguig City',
        shopName: 'Preloved Gems',
        rating: 4.9,
        sales: 412,
        isVerified: true,
        bio: 'Quality preloved items only 💎 | COD available | Taguig meetup OK',
        lastActive: DateTime.now().subtract(const Duration(hours: 8)),
        trustScore: 92,
      ),
    ),
  };

  AuthResult authenticate(String username, String password) {
    final normalized = username.trim().toLowerCase();
    final credential = _credentials[normalized];
    if (credential == null || credential.password != password) {
      return AuthResult.failure(_invalidCredentialsMessage);
    }
    return AuthResult.success(credential.user);
  }

  AuthUser? getUserByUsername(String username) =>
      _credentials[username.trim().toLowerCase()]?.user;

  void updateUser(AuthUser updatedUser) {
    final key = updatedUser.username.trim().toLowerCase();
    if (_credentials.containsKey(key)) {
      _credentials[key] = _Credential(
        password: _credentials[key]!.password,
        user: updatedUser,
      );
    }
  }

  List<AuthUser> get sellers =>
      _credentials.values.map((c) => c.user).where((u) => u.isSeller).toList();
}

class _Credential {
  const _Credential({required this.password, required this.user});
  final String password;
  final AuthUser user;
}
