class MarketplaceReportPayload {
  const MarketplaceReportPayload({
    required this.success,
    required this.category,
    required this.generatedAt,
    required this.rangeFrom,
    required this.rangeTo,
    this.compareFrom,
    this.compareTo,
    required this.summary,
    required this.comparison,
    required this.breakdowns,
    required this.details,
    required this.detailTotal,
    required this.limitations,
    this.error,
    this.completeBundle,
  });

  final bool success;
  final String category;
  final DateTime? generatedAt;
  final DateTime? rangeFrom;
  final DateTime? rangeTo;
  final DateTime? compareFrom;
  final DateTime? compareTo;
  final List<MarketplaceReportMetric> summary;
  final List<MarketplaceReportComparisonRow> comparison;
  final List<MarketplaceReportBreakdown> breakdowns;
  final MarketplaceReportDetails details;
  final int detailTotal;
  final List<String> limitations;
  final String? error;
  final Map<String, MarketplaceReportPayload>? completeBundle;

  factory MarketplaceReportPayload.fromJson(Map<String, dynamic> json) {
    if (json['category'] == 'all') {
      final bundles = <String, MarketplaceReportPayload>{};
      for (final key in [
        'users',
        'orders',
        'payments',
        'auctions',
        'disputes',
        'verifications',
        'security',
      ]) {
        final raw = asStringKeyMap(json[key]);
        if (raw != null) {
          bundles[key] = MarketplaceReportPayload.fromCategoryBundle(
            key,
            raw,
            json,
          );
        }
      }
      return MarketplaceReportPayload(
        success: json['success'] == true,
        category: 'all',
        generatedAt: parseReportDate(json['generated_at']),
        rangeFrom: parseReportDate(json['range_from']),
        rangeTo: parseReportDate(json['range_to']),
        compareFrom: parseReportDate(json['compare_from']),
        compareTo: parseReportDate(json['compare_to']),
        summary: parseReportMetrics(
          (json['overview'] as Map?)?['summary'],
        ),
        comparison: parseReportComparison(
          (json['overview'] as Map?)?['comparison'],
        ),
        breakdowns: const [],
        details: MarketplaceReportDetails.empty,
        detailTotal: 0,
        limitations: parseStringList(json['limitations']),
        error: json['error']?.toString(),
        completeBundle: bundles,
      );
    }

    return MarketplaceReportPayload(
      success: json['success'] == true,
      category: (json['category'] as String?) ?? 'overview',
      generatedAt: parseReportDate(json['generated_at']),
      rangeFrom: parseReportDate(json['range_from']),
      rangeTo: parseReportDate(json['range_to']),
      compareFrom: parseReportDate(json['compare_from']),
      compareTo: parseReportDate(json['compare_to']),
      summary: parseReportMetrics(json['summary']),
      comparison: parseReportComparison(json['comparison']),
      breakdowns: parseReportBreakdowns(json['breakdowns']),
      details: MarketplaceReportDetails.fromJson(asStringKeyMap(json['details'])),
      detailTotal: asReportInt(json['detail_total']),
      limitations: parseStringList(json['limitations']),
      error: json['error']?.toString(),
    );
  }

  factory MarketplaceReportPayload.fromCategoryBundle(
    String category,
    Map<String, dynamic> bundle,
    Map<String, dynamic> root,
  ) {
    return MarketplaceReportPayload(
      success: root['success'] == true,
      category: category,
      generatedAt: parseReportDate(root['generated_at']),
      rangeFrom: parseReportDate(root['range_from']),
      rangeTo: parseReportDate(root['range_to']),
      compareFrom: parseReportDate(root['compare_from']),
      compareTo: parseReportDate(root['compare_to']),
      summary: parseReportMetrics(bundle['summary']),
      comparison: parseReportComparison(bundle['comparison']),
      breakdowns: parseReportBreakdowns(bundle['breakdowns']),
      details: MarketplaceReportDetails.fromJson(asStringKeyMap(bundle['details'])),
      detailTotal: asReportInt(bundle['detail_total']),
      limitations: parseStringList(bundle['limitations']),
    );
  }
}

class MarketplaceReportMetric {
  const MarketplaceReportMetric({
    required this.key,
    required this.label,
    required this.value,
    required this.kind,
    required this.display,
    required this.snapshot,
  });

  final String key;
  final String label;
  final num value;
  final String kind;
  final String display;
  final bool snapshot;
}

class MarketplaceReportComparisonRow {
  const MarketplaceReportComparisonRow({
    required this.key,
    required this.label,
    required this.current,
    required this.previous,
    required this.changePct,
  });

  final String key;
  final String label;
  final num current;
  final num previous;
  final double? changePct;
}

class MarketplaceReportBreakdown {
  const MarketplaceReportBreakdown({
    required this.title,
    required this.columns,
    required this.rows,
  });

  final String title;
  final List<String> columns;
  final List<List<String>> rows;
}

class MarketplaceReportDetails {
  const MarketplaceReportDetails({
    required this.columns,
    required this.rows,
    required this.total,
    required this.truncated,
  });

  final List<String> columns;
  final List<List<Object?>> rows;
  final int total;
  final bool truncated;

  static const empty = MarketplaceReportDetails(
    columns: [],
    rows: [],
    total: 0,
    truncated: false,
  );

  factory MarketplaceReportDetails.fromJson(Map<String, dynamic>? json) {
    if (json == null) return empty;
    final columns = (json['columns'] as List?)
            ?.map((e) => e.toString())
            .toList(growable: false) ??
        const [];
    final rawRows = json['rows'] as List? ?? const [];
    final rows = rawRows
        .map((row) {
          if (row is! List) return <Object?>[];
          return row.map((cell) => cell).toList(growable: false);
        })
        .toList(growable: false);
    return MarketplaceReportDetails(
      columns: columns,
      rows: rows,
      total: asReportInt(json['total']),
      truncated: json['truncated'] == true,
    );
  }
}

/// PostgREST jsonb objects are often [Map<dynamic, dynamic>], not [Map<String, dynamic>].
Map<String, dynamic>? asStringKeyMap(Object? raw) {
  if (raw == null) return null;
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return null;
}

DateTime? parseReportDate(Object? raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw.toUtc();
  return DateTime.tryParse(raw.toString())?.toUtc();
}

int asReportInt(Object? raw, [int fallback = 0]) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '') ?? fallback;
}

double? asReportDouble(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString());
}

List<String> parseStringList(Object? raw) {
  if (raw is! List) return const [];
  return raw.map((e) => e.toString()).toList(growable: false);
}

List<MarketplaceReportMetric> parseReportMetrics(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((m) {
        final map = Map<String, dynamic>.from(m);
        return MarketplaceReportMetric(
          key: map['key']?.toString() ?? '',
          label: map['label']?.toString() ?? '',
          value: asReportDouble(map['value']) ?? 0,
          kind: map['kind']?.toString() ?? 'count',
          display: map['display']?.toString() ?? '',
          snapshot: map['snapshot'] == true,
        );
      })
      .toList(growable: false);
}

List<MarketplaceReportComparisonRow> parseReportComparison(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((m) {
        final map = Map<String, dynamic>.from(m);
        return MarketplaceReportComparisonRow(
          key: map['key']?.toString() ?? '',
          label: map['label']?.toString() ?? '',
          current: asReportDouble(map['current']) ?? 0,
          previous: asReportDouble(map['previous']) ?? 0,
          changePct: asReportDouble(map['change_pct']),
        );
      })
      .toList(growable: false);
}

List<MarketplaceReportBreakdown> parseReportBreakdowns(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((m) {
        final map = Map<String, dynamic>.from(m);
        final columns = (map['columns'] as List?)
                ?.map((e) => e.toString())
                .toList(growable: false) ??
            const [];
        final rowsRaw = map['rows'] as List? ?? const [];
        final rows = rowsRaw
            .map((row) {
              if (row is! List) return <String>[];
              return row.map((c) => c?.toString() ?? '').toList(growable: false);
            })
            .toList(growable: false);
        return MarketplaceReportBreakdown(
          title: map['title']?.toString() ?? '',
          columns: columns,
          rows: rows,
        );
      })
      .toList(growable: false);
}
