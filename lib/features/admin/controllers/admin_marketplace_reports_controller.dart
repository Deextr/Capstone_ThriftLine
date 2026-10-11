import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../data/admin_audit_service.dart';
import '../data/admin_marketplace_report_service.dart';
import '../data/marketplace_report_models.dart';
import '../domain/marketplace_report_catalog.dart';

class AdminMarketplaceReportsController extends ChangeNotifier {
  AdminMarketplaceReportsController({
    required SupabaseService supabase,
    required bool isSuperAdmin,
    MarketplaceReportSelection initialSelection =
        const MarketplaceReportSelection.all(),
  })  : _service = AdminMarketplaceReportService(supabase),
        _audit = AdminAuditService(supabase),
        _isSuperAdmin = isSuperAdmin,
        _selection = initialSelection {
    load();
  }

  @visibleForTesting
  AdminMarketplaceReportsController.preview({
    required MarketplaceReportPayload payload,
    MarketplaceReportSelection selection = const MarketplaceReportSelection.all(),
    bool isSuperAdmin = false,
  })  : _service = AdminMarketplaceReportService(_PreviewSupabase()),
        _audit = AdminAuditService(_PreviewSupabase()),
        _isSuperAdmin = isSuperAdmin,
        _selection = selection,
        _payload = payload,
        _isLoading = false;

  final AdminMarketplaceReportService _service;
  final AdminAuditService _audit;
  final bool _isSuperAdmin;

  MarketplaceReportSelection _selection;
  MarketplaceReportDateWindow _window = MarketplaceReportDateWindow.thisMonth();
  final Map<String, String> _filters = {};
  int _page = 0;
  int _paymentsPage = 0;
  int _loadGeneration = 0;
  bool _isLoading = true;
  bool _isExporting = false;
  String? _errorMessage;
  MarketplaceReportPayload? _payload;
  MarketplaceReportPayload? _paymentsPayload;

  MarketplaceReportSelection get selection => _selection;
  bool get isAllReportTypes => _selection.isAll;
  MarketplaceReportCategory get category => _selection.singleCategory;
  MarketplaceReportDateWindow get window => _window;
  Map<String, String> get filters => Map.unmodifiable(_filters);
  int get page => _page;
  bool get isLoading => _isLoading;
  bool get isExporting => _isExporting;
  String? get errorMessage => _errorMessage;
  MarketplaceReportPayload? get payload => _payload;
  MarketplaceReportPayload? get paymentsPayload => _paymentsPayload;
  int get paymentsPage => _paymentsPage;
  bool get isSuperAdmin => _isSuperAdmin;
  bool get hasActiveFilters => _filters.isNotEmpty;

  int get pageSize => marketplaceReportPageSize;
  int get detailTotal => _payload?.detailTotal ?? 0;
  int get pageCount =>
      detailTotal == 0 ? 1 : ((detailTotal - 1) ~/ pageSize) + 1;

  void applyReportType(MarketplaceReportSelection selection) {
    if (_selection.isAll == selection.isAll &&
        (_selection.isAll ||
            _selection.singleCategory == selection.singleCategory)) {
      return;
    }
    _selection = selection;
    _page = 0;
    _paymentsPage = 0;
    _stripIrrelevantFilters();
    _payload = null;
    load();
  }

  void _stripIrrelevantFilters() {
    if (_selection.isAll) {
      _filters.clear();
      return;
    }
    final allowed = adminReportFilterKeys(_selection.type).toSet();
    _filters.removeWhere((key, _) => !allowed.contains(key));
  }

  void setWindow(MarketplaceReportDateWindow window) {
    _window = window;
    _page = 0;
    _paymentsPage = 0;
    load();
  }

  void setFilter(String key, String? value) {
    if (value == null || value.isEmpty) {
      _filters.remove(key);
    } else {
      _filters[key] = value;
    }
    _page = 0;
    _paymentsPage = 0;
    load();
  }

  void resetFilters() {
    _filters.clear();
    _page = 0;
    _paymentsPage = 0;
    load();
  }

  void setPage(int page) {
    final clamped = page.clamp(0, pageCount - 1);
    if (_page == clamped) return;
    _page = clamped;
    load();
  }

  void setPaymentsPage(int page) {
    final total = _paymentsPayload?.detailTotal ?? 0;
    final count = total == 0 ? 1 : ((total - 1) ~/ pageSize) + 1;
    final clamped = page.clamp(0, count - 1);
    if (_paymentsPage == clamped) return;
    _paymentsPage = clamped;
    load();
  }

  Future<void> load() async {
    final generation = ++_loadGeneration;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _service.loadReport(
        category: _selection.isAll
            ? MarketplaceReportCategory.overview
            : _selection.singleCategory,
        window: _window,
        filters: _filters,
        limit: pageSize,
        offset: _selection.isAll ? 0 : _page * pageSize,
        complete: _selection.isAll,
      );
      if (generation != _loadGeneration) return;
      _payload = result;
      _paymentsPayload = null;
      if (_selection.type == AdminReportType.ordersTransactions && result.success) {
        _paymentsPayload = await _service.loadReport(
          category: MarketplaceReportCategory.payments,
          window: _window,
          filters: _filters,
          limit: 0,
          offset: 0,
        );
      }
      if (generation != _loadGeneration) return;
      if (result.success != true) {
        _errorMessage = result.error ?? 'Unable to load report.';
      } else if (result.summary.isEmpty &&
          result.details.rows.isEmpty &&
          result.breakdowns.isEmpty) {
        // Still valid — empty period.
      }
    } catch (e) {
      if (generation != _loadGeneration) return;
      debugPrint('AdminMarketplaceReportsController.load: $e');
      _payload = null;
      _paymentsPayload = null;
      _errorMessage = marketplaceReportErrorMessage(e);
    } finally {
      if (generation == _loadGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<MarketplaceReportPayload?> loadForExport({
    void Function(double progress)? onProgress,
  }) async {
    try {
      onProgress?.call(0.05);
      if (_selection.isAll) {
        onProgress?.call(0.4);
        return await _service.loadReport(
          category: MarketplaceReportCategory.overview,
          window: _window,
          filters: const {},
          limit: marketplaceReportExportDetailCap,
          offset: 0,
          complete: true,
        );
      }

      if (_selection.type == AdminReportType.ordersTransactions) {
        final orders = await _loadCategoryForExport(
          MarketplaceReportCategory.orders,
          onProgress: (p) => onProgress?.call(0.05 + p * 0.4),
        );
        onProgress?.call(0.5);
        final payments = await _loadCategoryForExport(
          MarketplaceReportCategory.payments,
          onProgress: (p) => onProgress?.call(0.5 + p * 0.4),
        );
        onProgress?.call(0.92);
        if (orders == null || payments == null) return orders ?? payments;
        return _combineOrdersAndPayments(orders, payments);
      }

      return _loadCategoryForExport(
        _selection.singleCategory,
        onProgress: onProgress,
      );
    } catch (e) {
      debugPrint('AdminMarketplaceReportsController.loadForExport: $e');
      return null;
    }
  }

  Future<MarketplaceReportPayload?> _loadCategoryForExport(
    MarketplaceReportCategory category, {
    void Function(double progress)? onProgress,
  }) async {
    final first = await _service.loadReport(
      category: category,
      window: _window,
      filters: _filters,
      limit: marketplaceReportExportDetailCap,
      offset: 0,
      complete: false,
    );
    if (!first.success) return first;

    final total = first.detailTotal;
    if (onProgress != null) {
      onProgress(
        total <= 0
            ? 1.0
            : (first.details.rows.length / total).clamp(0.05, 1.0),
      );
    }
    if (total <= first.details.rows.length) return first;

    final allRows = [...first.details.rows];
    var offset = allRows.length;
    while (offset < total) {
      final chunk = await _service.loadReport(
        category: category,
        window: _window,
        filters: _filters,
        limit: marketplaceReportExportDetailCap,
        offset: offset,
        complete: false,
      );
      if (!chunk.success || chunk.details.rows.isEmpty) break;
      allRows.addAll(chunk.details.rows);
      offset += chunk.details.rows.length;
      onProgress?.call((offset / total).clamp(0.0, 1.0));
      if (chunk.details.rows.length < marketplaceReportExportDetailCap) break;
    }
    onProgress?.call(1.0);

    return MarketplaceReportPayload(
      success: first.success,
      category: first.category,
      generatedAt: first.generatedAt,
      rangeFrom: first.rangeFrom,
      rangeTo: first.rangeTo,
      compareFrom: first.compareFrom,
      compareTo: first.compareTo,
      summary: first.summary,
      comparison: first.comparison,
      breakdowns: first.breakdowns,
      details: MarketplaceReportDetails(
        columns: first.details.columns,
        rows: allRows,
        total: total,
        truncated: allRows.length < total,
      ),
      detailTotal: total,
      limitations: first.limitations,
      error: first.error,
      completeBundle: first.completeBundle,
    );
  }

  MarketplaceReportPayload _combineOrdersAndPayments(
    MarketplaceReportPayload orders,
    MarketplaceReportPayload payments,
  ) {
    return MarketplaceReportPayload(
      success: orders.success && payments.success,
      category: 'orders_transactions',
      generatedAt: orders.generatedAt ?? payments.generatedAt,
      rangeFrom: orders.rangeFrom,
      rangeTo: orders.rangeTo,
      summary: [...orders.summary, ...payments.summary],
      comparison: const [],
      breakdowns: [...orders.breakdowns, ...payments.breakdowns],
      details: orders.details,
      detailTotal: orders.detailTotal,
      limitations: [...orders.limitations, ...payments.limitations],
      error: orders.error ?? payments.error,
    );
  }

  Future<void> recordExport({
    required String format,
    required String scope,
  }) async {
    await _audit.record(
      category: 'system_security',
      eventType: 'marketplace_report_exported',
      status: 'success',
      summary: 'Exported marketplace report ($format, $scope)',
      details: {
        'format': format,
        'scope': scope,
        'category': _selection.queryValue,
        'window_from': _window.from.toIso8601String(),
        'window_to': _window.toExclusive.toIso8601String(),
        'filters': _filters,
      },
    );
  }

  void setExporting(bool value) {
    _isExporting = value;
    notifyListeners();
  }
}

class _PreviewSupabase implements SupabaseService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
