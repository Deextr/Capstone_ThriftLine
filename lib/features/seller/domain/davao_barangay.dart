/// A barangay that is allowed for seller shop addresses — Davao City only.
class DavaoBarangay {
  const DavaoBarangay({
    required this.code,
    required this.name,
    required this.cityCode,
  });

  final String code;
  final String name;
  final String cityCode;

  /// PSA / PSGC codes for the City of Davao (9-digit and 10-digit).
  static const String cityCodePsgc9 = '112402000';
  static const String cityCodePsgc10 = '1130700000';
  static const String cityName = 'Davao City';

  bool get isDavaoCity =>
      cityCode == cityCodePsgc9 || cityCode == cityCodePsgc10;

  /// Parses a PSGC barangay payload and keeps only Davao City rows.
  ///
  /// Duplicates (same code or same name, case-insensitive) are collapsed.
  /// Rows for other cities, municipalities, or missing names are dropped.
  static List<DavaoBarangay> fromApiList(Object? raw) {
    if (raw is! List) {
      throw const FormatException('Barangay list was not a JSON array.');
    }

    final byCode = <String, DavaoBarangay>{};
    final seenNames = <String>{};

    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final parsed = _tryParse(map);
      if (parsed == null || !parsed.isDavaoCity) continue;

      final nameKey = parsed.name.toLowerCase();
      if (byCode.containsKey(parsed.code) || seenNames.contains(nameKey)) {
        continue;
      }
      byCode[parsed.code] = parsed;
      seenNames.add(nameKey);
    }

    final list = byCode.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  static DavaoBarangay? _tryParse(Map<String, dynamic> map) {
    final name = (map['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return null;

    final code = '${map['code'] ?? map['psgc10DigitCode'] ?? ''}'.trim();
    if (code.isEmpty) return null;

    final cityCode = _readCityCode(map);
    if (cityCode == null) return null;
    if (!_isDavaoCityCode(cityCode)) return null;

    // Municipality-only rows must not leak in if the API mixes geo levels.
    final municipality = map['municipalityCode'];
    if (municipality is String &&
        municipality.isNotEmpty &&
        municipality != 'false') {
      return null;
    }

    return DavaoBarangay(code: code, name: name, cityCode: cityCode);
  }

  static String? _readCityCode(Map<String, dynamic> map) {
    final city = map['cityCode'];
    if (city is String && city.trim().isNotEmpty && city != 'false') {
      return city.trim();
    }
    final ten = map['psgc10DigitCode'];
    if (ten is String && ten.length >= 7 && ten.startsWith('1130700')) {
      return cityCodePsgc10;
    }
    return null;
  }

  static bool _isDavaoCityCode(String code) =>
      code == cityCodePsgc9 || code == cityCodePsgc10;

  static bool isAllowedSelection(
    DavaoBarangay? selected,
    List<DavaoBarangay> loaded,
  ) {
    if (selected == null || !selected.isDavaoCity) return false;
    return loaded.any(
      (item) => item.code == selected.code && item.isDavaoCity,
    );
  }
}

class DavaoBarangayException implements Exception {
  const DavaoBarangayException(this.kind, [this.message]);

  final DavaoBarangayErrorKind kind;
  final String? message;

  String get userMessage => switch (kind) {
        DavaoBarangayErrorKind.timeout =>
          'The barangay list took too long to load. Check your connection and try again.',
        DavaoBarangayErrorKind.network =>
          'Could not load Davao City barangays. Check your connection and try again.',
        DavaoBarangayErrorKind.invalid =>
          'The barangay list came back in an unexpected format. Please try again.',
        DavaoBarangayErrorKind.empty =>
          'No Davao City barangays were returned. Please try again.',
      };

  @override
  String toString() => message ?? userMessage;
}

enum DavaoBarangayErrorKind { timeout, network, invalid, empty }
