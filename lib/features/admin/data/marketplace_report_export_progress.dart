/// Progress updates for marketplace report exports (0.0–1.0).
class MarketplaceReportExportProgress {
  const MarketplaceReportExportProgress(this.fraction, this.message);

  final double fraction;
  final String message;

  int get percent => (fraction.clamp(0.0, 1.0) * 100).round();
}

typedef MarketplaceReportExportProgressCallback = void Function(
  MarketplaceReportExportProgress progress,
);
