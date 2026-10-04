import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/ai_search_parser.dart';

import '../support/qa_reporter.dart';

void aiSearchParserUnitTests() {
  qaGroup('AI search parser', () {
    qaUnitTest('extracts category, size, max price and style', () {
      final result = parseAiSearch('Vintage denim jacket size M under ₱500');

      expect(result.category, 'Outerwear');
      expect(result.size, 'M');
      expect(result.priceMax, 500);
      expect(result.priceMin, isNull);
      expect(result.style, 'VINTAGE');
    });

    qaUnitTest('keywords drop stop-words and short tokens', () {
      final result = parseAiSearch('Vintage denim jacket size M under ₱500');

      expect(result.keywords, containsAll(['vintage', 'denim', 'jacket']));
      expect(result.keywords, isNot(contains('size')));
      expect(result.keywords, isNot(contains('under')));
      expect(result.keywords, isNot(contains('m')));
    });

    qaUnitTest('reads a price range', () {
      final result = parseAiSearch('y2k tee ₱200-₱450');

      expect(result.category, 'Tops');
      expect(result.priceMin, 200);
      expect(result.priceMax, 450);
      expect(result.style, 'Y2K');
    });

    qaUnitTest('reads numeric shoe sizes', () {
      final result = parseAiSearch('sneakers size 42');

      expect(result.category, 'Shoes');
      expect(result.size, '42');
    });

    qaUnitTest('empty query returns an empty result', () {
      final result = parseAiSearch('');

      expect(result.category, isNull);
      expect(result.size, isNull);
      expect(result.priceMin, isNull);
      expect(result.priceMax, isNull);
      expect(result.style, isNull);
      expect(result.keywords, isEmpty);
    });

    qaGroup('aiUnderstandingText', () {
      qaUnitTest('falls back to "Searching all items"', () {
        expect(
          aiUnderstandingText(const AiSearchResult()),
          '🤖 AI understands: Searching all items',
        );
      });

      qaUnitTest('joins every detected part with bullets', () {
        expect(
          aiUnderstandingText(
            const AiSearchResult(
              category: 'Outerwear',
              size: 'M',
              priceMax: 500,
              style: 'VINTAGE',
            ),
          ),
          '🤖 AI understands: Outerwear • Size M • Under ₱500 • VINTAGE',
        );
      });

      qaUnitTest('formats ranges and minimum-only prices', () {
        expect(
          aiUnderstandingText(
            const AiSearchResult(priceMin: 200, priceMax: 450),
          ),
          '🤖 AI understands: ₱200–₱450',
        );
        expect(
          aiUnderstandingText(const AiSearchResult(priceMin: 300)),
          '🤖 AI understands: From ₱300',
        );
      });
    });
  });
}
