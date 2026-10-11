import 'dart:async';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/utils/formatters.dart';
import '../domain/marketplace_report_catalog.dart';
import 'marketplace_report_download.dart';
import 'marketplace_report_export_progress.dart';
import 'marketplace_report_models.dart';

class MarketplaceReportExporter {
  static final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');
  static final _fileDateFmt = DateFormat('yyyyMMdd_HHmm');
  static final _brandTeal = PdfColor.fromHex('0D9488');
  static final _headerBand = PdfColor.fromHex('F0FDFA');

  static pw.Font? _cachedBaseFont;
  static pw.Font? _cachedBoldFont;
  static Uint8List? _cachedLogoBytes;
  static Future<void>? _pdfAssetsPreload;

  /// Warm fonts and logo so the first PDF export stays responsive.
  static Future<void> preloadPdfAssets() {
    _pdfAssetsPreload ??= _preloadPdfAssets();
    return _pdfAssetsPreload!;
  }

  static Future<void> _preloadPdfAssets() async {
    await Future.wait([
      _ensurePdfFonts(),
      _ensureLogoBytes(),
    ]);
  }

  static Future<void> _ensurePdfFonts() async {
    _cachedBaseFont ??= await PdfGoogleFonts.notoSansRegular();
    _cachedBoldFont ??= await PdfGoogleFonts.notoSansBold();
  }

  static Future<Uint8List?> _ensureLogoBytes() async {
    if (_cachedLogoBytes != null) return _cachedLogoBytes;
    for (final path in [
      'assets/images/thriftline-app-icon.png',
      'assets/images/thriftline-logo.png',
    ]) {
      try {
        final data = await rootBundle.load(path);
        _cachedLogoBytes = data.buffer.asUint8List();
        return _cachedLogoBytes;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  static Future<void> _pumpUi() async {
    await Future<void>.delayed(Duration.zero);
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      await SchedulerBinding.instance.endOfFrame;
    }
  }

  static void _reportProgress(
    MarketplaceReportExportProgressCallback? onProgress,
    double fraction,
    String message,
  ) {
    onProgress?.call(MarketplaceReportExportProgress(fraction, message));
  }

  static Future<void> exportPdf({
    required MarketplaceReportPayload payload,
    required MarketplaceReportCategory category,
    required MarketplaceReportDateWindow window,
    required Map<String, String> filters,
    required bool complete,
    String? title,
    MarketplaceReportExportProgressCallback? onProgress,
  }) async {
    _reportProgress(onProgress, 0.02, 'Loading fonts…');
    await _ensurePdfFonts();
    await _pumpUi();

    _reportProgress(onProgress, 0.08, 'Loading brand assets…');
    final logoBytes = await _ensureLogoBytes();
    await _pumpUi();

    final heading = title ??
        (complete ? 'All Reports' : marketplaceReportCategoryLabel(category));

    _reportProgress(onProgress, 0.14, 'Assembling report…');
    await _pumpUi();

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: _cachedBaseFont!,
        bold: _cachedBoldFont!,
      ),
    );
    final logo =
        logoBytes != null ? pw.MemoryImage(logoBytes) : null;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 40),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'ThriftLine Marketplace Report',
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ],
        ),
        build: (context) => [
          _pdfCoverHeader(
            logo: logo,
            heading: heading,
            window: window,
            filters: filters,
          ),
          pw.SizedBox(height: 20),
          ..._pdfSections(payload, complete),
        ],
      ),
    );

    _reportProgress(onProgress, 0.42, 'Rendering PDF…');
    await _pumpUi();
    await Future<void>.delayed(const Duration(milliseconds: 280));

    final bytes = await _savePdfDocument(
      doc,
      onProgress: (fraction) {
        _reportProgress(
          onProgress,
          0.42 + fraction * 0.52,
          'Rendering PDF…',
        );
      },
    );
    if (bytes.isEmpty) {
      throw StateError('PDF export produced no data.');
    }

    _reportProgress(onProgress, 0.97, 'Starting download…');
    await _pumpUi();
    await _download(
      bytes,
      'thriftline_report_${_fileDateFmt.format(DateTime.now())}.pdf',
      'application/pdf',
    );
    _reportProgress(onProgress, 1.0, 'Download complete');
    await _pumpUi();
  }

  static Future<Uint8List> _savePdfDocument(
    pw.Document doc, {
    required void Function(double fraction) onProgress,
  }) async {
    onProgress(0.02);
    await _pumpUi();

    final completer = Completer<Uint8List>();
    var tick = 0;
    Timer? timer;
    timer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      tick++;
      final simulated = (tick * 0.05).clamp(0.0, 0.85);
      onProgress(simulated);
    });

    scheduleMicrotask(() {
      try {
        final bytes = doc.save();
        onProgress(1.0);
        completer.complete(bytes);
      } catch (e, st) {
        completer.completeError(e, st);
      } finally {
        timer?.cancel();
      }
    });

    await _pumpUi();
    return completer.future;
  }

  static List<pw.Widget> _pdfSections(
    MarketplaceReportPayload payload,
    bool complete,
  ) {
    if (complete && payload.completeBundle != null) {
      final widgets = <pw.Widget>[];
      widgets.addAll(_pdfBlock('Overview', payload.summary, payload.comparison, payload.breakdowns));
      for (final entry in payload.completeBundle!.entries) {
        final cat = MarketplaceReportCategory.values.firstWhere(
          (c) => marketplaceReportCategoryRpcValue(c) == entry.key,
          orElse: () => MarketplaceReportCategory.overview,
        );
        widgets.add(pw.NewPage());
        widgets.addAll(_pdfBlock(
          marketplaceReportCategoryLabel(cat),
          entry.value.summary,
          entry.value.comparison,
          entry.value.breakdowns,
          entry.key == 'payments' ? null : entry.value.details,
        ));
      }
      return widgets;
    }
    return _pdfBlock(
      marketplaceReportCategoryLabel(
        MarketplaceReportCategory.values.firstWhere(
          (c) => marketplaceReportCategoryRpcValue(c) == payload.category,
          orElse: () => MarketplaceReportCategory.overview,
        ),
      ),
      payload.summary,
      payload.comparison,
      payload.breakdowns,
      payload.details,
    );
  }

  static List<pw.Widget> _pdfBlock(
    String heading,
    List<MarketplaceReportMetric> summary,
    List<MarketplaceReportComparisonRow> comparison,
    List<MarketplaceReportBreakdown> breakdowns, [
    MarketplaceReportDetails? details,
  ]) {
    final widgets = <pw.Widget>[
      _pdfSectionTitle(heading),
      pw.SizedBox(height: 10),
    ];
    if (summary.isNotEmpty) {
      widgets.add(_pdfSubsectionTitle('Summary'));
      widgets.add(_pdfTable(
        ['Metric', 'Value'],
        summary.map((m) => [m.label, _pdfMetricDisplay(m)]).toList(),
      ));
      widgets.add(pw.SizedBox(height: 12));
    }
    if (comparison.isNotEmpty) {
      widgets.add(_pdfSubsectionTitle('Comparison'));
      widgets.add(_pdfTable(
        ['Metric', 'Current', 'Previous', 'Change'],
        comparison
            .map(
              (r) => [
                r.label,
                r.current.toString(),
                r.previous.toString(),
                formatMarketplaceReportChange(r.changePct),
              ],
            )
            .toList(),
      ));
      widgets.add(pw.SizedBox(height: 12));
    }
    for (final b in breakdowns) {
      widgets.add(_pdfSubsectionTitle(b.title));
      widgets.add(
        _pdfTable(
          b.columns.map(_pdfFixPesoInText).toList(),
          b.rows
              .map(
                (row) => _pdfFormatDetailRow(b.columns, row),
              )
              .toList(),
        ),
      );
      widgets.add(pw.SizedBox(height: 12));
    }
    if (details != null && details.rows.isNotEmpty) {
      widgets.add(_pdfSubsectionTitle('Detailed records'));
      widgets.add(
        _pdfTable(
          details.columns.map(_pdfFixPesoInText).toList(),
          details.rows.map((row) => _pdfFormatDetailRow(details.columns, row)).toList(),
        ),
      );
    }
    return widgets;
  }

  static pw.Widget _pdfCoverHeader({
    required pw.ImageProvider? logo,
    required String heading,
    required MarketplaceReportDateWindow window,
    required Map<String, String> filters,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: pw.BoxDecoration(
        color: _headerBand,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColor.fromHex('CCFBF1')),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logo != null) ...[
                pw.Image(logo, height: 40, width: 40),
                pw.SizedBox(width: 12),
              ],
              pw.Text(
                'ThriftLine',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                  color: _brandTeal,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            heading,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey800,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Period (Philippines): ${window.chipLabel}',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.Text(
            'Generated: ${_dateFmt.format(DateTime.now())}',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          if (filters.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(
                'Filters: ${filters.entries.map((e) => '${e.key}=${e.value}').join(', ')}',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
            ),
        ],
      ),
    );
  }

  static pw.Widget _pdfSectionTitle(String text) {
    return pw.Center(
      child: pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(vertical: 6),
        decoration: pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: _brandTeal, width: 1.5),
          ),
        ),
        child: pw.Text(
          text,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: _brandTeal,
          ),
        ),
      ),
    );
  }

  static pw.Widget _pdfSubsectionTitle(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Center(
        child: pw.Text(
          text,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey800,
          ),
        ),
      ),
    );
  }

  static String _pdfMetricDisplay(MarketplaceReportMetric metric) {
    if (metric.kind == 'money') {
      return formatAdminReportPesoAmount(metric.value.toString());
    }
    return _pdfFixPesoInText(metric.display);
  }

  static List<String> _pdfFormatDetailRow(
    List<String> columns,
    List<dynamic> row,
  ) {
    return [
      for (var i = 0; i < row.length; i++)
        _pdfFormatDetailCell(
          i < columns.length ? columns[i] : '',
          row[i]?.toString() ?? '',
        ),
    ];
  }

  static String _pdfFormatDetailCell(String columnHeader, String raw) {
    final header = columnHeader.trim().toLowerCase();
    if (header == 'total' ||
        header == 'amount' ||
        header.contains('total') ||
        header.contains('₱') ||
        header.contains('peso')) {
      return formatAdminReportPesoAmount(raw);
    }
    return _pdfFixPesoInText(raw);
  }

  static String _pdfFixPesoInText(String text) {
    if (text.contains('â‚±') ||
        text.contains('₱') ||
        text.contains('\u20B1')) {
      final normalized = formatAdminReportPesoAmount(text);
      if (normalized != text || text.contains('â‚±')) {
        return normalized;
      }
    }
    return text;
  }

  static pw.Widget _pdfTable(List<String> headers, List<List<String>> rows) {
    final headerAlignments = {
      for (var i = 0; i < headers.length; i++) i: pw.Alignment.center,
    };
    return pw.Table.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        fontSize: 9,
        color: PdfColors.grey900,
      ),
      cellStyle: const pw.TextStyle(fontSize: 9),
      headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('E6FFFA')),
      cellAlignment: pw.Alignment.centerLeft,
      headerAlignments: headerAlignments,
      cellAlignments: {
        0: pw.Alignment.centerLeft,
      },
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
    );
  }

  static Future<void> exportExcel({
    required MarketplaceReportPayload payload,
    required MarketplaceReportCategory category,
    required MarketplaceReportDateWindow window,
    required Map<String, String> filters,
    required bool complete,
    String? title,
    MarketplaceReportExportProgressCallback? onProgress,
  }) async {
    _reportProgress(onProgress, 0.02, 'Creating workbook…');
    await _pumpUi();

    final excel = Excel.createExcel();
    excel.delete('Sheet1');

    _reportProgress(onProgress, 0.1, 'Writing summary…');
    await _pumpUi();
    _writeSummarySheet(
      excel,
      'Summary',
      payload,
      category,
      window,
      filters,
      complete,
      title: title,
    );

    if (complete && payload.completeBundle != null) {
      final entries = payload.completeBundle!.entries.toList();
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        final name = _sheetName(entry.key);
        final sheetProgress = 0.18 + (0.52 * (i + 1) / entries.length);
        _reportProgress(onProgress, sheetProgress, 'Writing $name sheet…');
        await _pumpUi();

        _writeSummarySheet(
          excel,
          name,
          entry.value,
          MarketplaceReportCategory.values.firstWhere(
            (c) => marketplaceReportCategoryRpcValue(c) == entry.key,
            orElse: () => MarketplaceReportCategory.overview,
          ),
          window,
          filters,
          false,
        );
        if (entry.key != 'payments') {
          _writeDetailSheet(excel, '${name}_Data', entry.value.details);
        }
      }
    } else {
      _reportProgress(onProgress, 0.35, 'Writing detailed data…');
      await _pumpUi();
      _writeDetailSheet(excel, 'Detailed Data', payload.details);
    }

    _reportProgress(onProgress, 0.78, 'Adding definitions…');
    await _pumpUi();
    _writeDefinitionsSheet(excel, payload.limitations);

    _reportProgress(onProgress, 0.82, 'Encoding spreadsheet…');
    await _pumpUi();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final bytes = await _encodeExcelWorkbook(
      excel,
      onProgress: (fraction) {
        _reportProgress(
          onProgress,
          0.82 + fraction * 0.14,
          'Encoding spreadsheet…',
        );
      },
    );
    if (bytes.isEmpty) {
      throw StateError('Excel export produced no data.');
    }

    _reportProgress(onProgress, 0.97, 'Starting download…');
    await _pumpUi();
    await _download(
      bytes,
      'thriftline_report_${_fileDateFmt.format(DateTime.now())}.xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    _reportProgress(onProgress, 1.0, 'Download complete');
    await _pumpUi();
  }

  static Future<Uint8List> _encodeExcelWorkbook(
    Excel excel, {
    required void Function(double fraction) onProgress,
  }) async {
    onProgress(0.05);
    await _pumpUi();

    final completer = Completer<Uint8List>();
    var tick = 0;
    Timer? timer;
    timer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      tick++;
      onProgress((tick * 0.06).clamp(0.0, 0.85));
    });

    scheduleMicrotask(() {
      try {
        final encoded = excel.encode();
        onProgress(1.0);
        if (encoded == null || encoded.isEmpty) {
          completer.completeError(
            StateError('Excel export produced no data.'),
          );
        } else {
          completer.complete(Uint8List.fromList(encoded));
        }
      } catch (e, st) {
        completer.completeError(e, st);
      } finally {
        timer?.cancel();
      }
    });

    await _pumpUi();
    return completer.future;
  }

  static String _sheetName(String key) {
    return switch (key) {
      'users' => 'Users',
      'orders' => 'Orders',
      'payments' => 'Payments',
      'auctions' => 'Auctions',
      'disputes' => 'Disputes',
      'verifications' => 'Verifications',
      'security' => 'Security',
      _ => key,
    };
  }

  static void _writeSummarySheet(
    Excel excel,
    String sheetName,
    MarketplaceReportPayload payload,
    MarketplaceReportCategory category,
    MarketplaceReportDateWindow window,
    Map<String, String> filters,
    bool complete, {
    String? title,
  }) {
    final sheet = excel[sheetName];
    var row = 0;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row++)).value =
        TextCellValue('ThriftLine Marketplace Report');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row++)).value =
        TextCellValue(
          title ??
              (complete ? 'All Reports' : marketplaceReportCategoryLabel(category)),
        );
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row++)).value =
        TextCellValue('Period: ${window.chipLabel}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row++)).value =
        TextCellValue('Generated: ${_dateFmt.format(DateTime.now())}');
    row++;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row++)).value =
        TextCellValue('Metric');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row - 1)).value =
        TextCellValue('Value');
    for (final m in payload.summary) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
          TextCellValue(sanitizeSpreadsheetCell(m.label));
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row));
      if (m.kind == 'money') {
        cell.value = DoubleCellValue(m.value.toDouble());
      } else if (m.kind == 'count' || m.kind == 'percent') {
        cell.value = DoubleCellValue(m.value.toDouble());
      } else {
        cell.value = TextCellValue(sanitizeSpreadsheetCell(m.display));
      }
      row++;
    }
  }

  static void _writeDetailSheet(Excel excel, String sheetName, MarketplaceReportDetails details) {
    if (excel.sheets.keys.contains(sheetName)) return;
    final sheet = excel[sheetName];
    for (var c = 0; c < details.columns.length; c++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).value =
          TextCellValue(sanitizeSpreadsheetCell(details.columns[c]));
    }
    for (var r = 0; r < details.rows.length; r++) {
      final row = details.rows[r];
      for (var c = 0; c < row.length; c++) {
        final value = row[c];
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1));
        if (value is num) {
          cell.value = DoubleCellValue(value.toDouble());
        } else {
          cell.value = TextCellValue(sanitizeSpreadsheetCell(value?.toString() ?? ''));
        }
      }
    }
    if (details.truncated) {
      final noteRow = details.rows.length + 2;
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: noteRow))
          .value = TextCellValue(
        'Export truncated at ${marketplaceReportExportDetailCap} rows.',
      );
    }
  }

  static void _writeDefinitionsSheet(Excel excel, List<String> limitations) {
    final sheet = excel['Definitions'];
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value =
        TextCellValue('Metric definitions and notes');
    var r = 2;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r++)).value =
        TextCellValue(
          'Platform revenue is ThriftLine platform fees on paid, non-refunded orders — not total buyer payments.',
        );
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r++)).value =
        TextCellValue(
          'Gross payment volume sums payment row amounts (multi-shop checkout = one row per seller).',
        );
    for (final note in limitations) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r++)).value =
          TextCellValue(sanitizeSpreadsheetCell(note));
    }
  }

  static Future<void> _download(Uint8List bytes, String name, String mime) async {
    downloadReportBytes(bytes: bytes, fileName: name, mimeType: mime);
  }
}
