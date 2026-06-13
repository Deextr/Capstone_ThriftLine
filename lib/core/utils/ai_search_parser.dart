class AiSearchResult {
  const AiSearchResult({
    this.category,
    this.size,
    this.priceMin,
    this.priceMax,
    this.style,
    this.keywords = const [],
  });

  final String? category;
  final String? size;
  final double? priceMin;
  final double? priceMax;
  final String? style;
  final List<String> keywords;
}

AiSearchResult parseAiSearch(String query) {
  final lower = query.toLowerCase();
  String? category;
  String? size;
  double? priceMin;
  double? priceMax;
  String? style;
  final keywords = <String>[];

  const categories = {
    'top': 'Tops',
    'shirt': 'Tops',
    'blouse': 'Tops',
    'tee': 'Tops',
    'bottom': 'Bottoms',
    'jean': 'Bottoms',
    'pants': 'Bottoms',
    'dress': 'Dresses',
    'jacket': 'Outerwear',
    'coat': 'Outerwear',
    'windbreaker': 'Outerwear',
    'blazer': 'Outerwear',
    'shoe': 'Shoes',
    'sneaker': 'Shoes',
    'boot': 'Shoes',
    'bag': 'Bags',
    'accessory': 'Accessories',
    'vintage': 'Vintage',
    'streetwear': 'Streetwear',
    'formal': 'Formal',
  };

  for (final entry in categories.entries) {
    if (lower.contains(entry.key)) {
      category = entry.value;
      break;
    }
  }

  final sizeMatch = RegExp(r'size\s*([xsml\d/]+)', caseSensitive: false).firstMatch(lower);
  if (sizeMatch != null) {
    size = sizeMatch.group(1)?.toUpperCase();
  } else {
    final numSize = RegExp(r'\b(\d{2,3})\b').firstMatch(lower);
    if (numSize != null) size = numSize.group(1);
  }

  final underMatch = RegExp(r'under\s*₱?\s*(\d+)', caseSensitive: false).firstMatch(lower);
  if (underMatch != null) {
    priceMax = double.tryParse(underMatch.group(1)!);
  }

  final rangeMatch = RegExp(r'₱?\s*(\d+)\s*[-–]\s*₱?\s*(\d+)').firstMatch(lower);
  if (rangeMatch != null) {
    priceMin = double.tryParse(rangeMatch.group(1)!);
    priceMax = double.tryParse(rangeMatch.group(2)!);
  }

  const styles = ['90s', 'y2k', 'vintage', 'korean', 'cottagecore', 'streetwear', 'baggy'];
  for (final s in styles) {
    if (lower.contains(s)) {
      style = s.toUpperCase();
      break;
    }
  }

  for (final word in lower.split(RegExp(r'\s+'))) {
    if (word.length > 2 &&
        !['the', 'for', 'and', 'size', 'under'].contains(word)) {
      keywords.add(word);
    }
  }

  return AiSearchResult(
    category: category,
    size: size,
    priceMin: priceMin,
    priceMax: priceMax,
    style: style,
    keywords: keywords,
  );
}

String aiUnderstandingText(AiSearchResult result) {
  final parts = <String>[];
  if (result.category != null) parts.add(result.category!);
  if (result.size != null) parts.add('Size ${result.size}');
  if (result.priceMin != null || result.priceMax != null) {
    if (result.priceMin != null && result.priceMax != null) {
      parts.add('₱${result.priceMin!.toInt()}–₱${result.priceMax!.toInt()}');
    } else if (result.priceMax != null) {
      parts.add('Under ₱${result.priceMax!.toInt()}');
    } else {
      parts.add('From ₱${result.priceMin!.toInt()}');
    }
  }
  if (result.style != null) parts.add(result.style!);
  if (parts.isEmpty) return '🤖 AI understands: Searching all items';
  return '🤖 AI understands: ${parts.join(' • ')}';
}
