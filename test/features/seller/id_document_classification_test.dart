import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/domain/id_document_classification.dart';
import 'package:thriftline/features/seller/domain/id_image_quality.dart';
import 'package:thriftline/features/seller/domain/seller_id_type.dart';

IdDocumentGeometry _card({double moduleScore = 0.1, double portrait = 0.18}) {
  return IdDocumentGeometry(
    occupancy: 0.72,
    aspectRatio: 1.58,
    bandCount: 4,
    borderScore: 0.4,
    solidity: 0.8,
    cornerFill: 0.6,
    interiorMean: 180,
    lightFraction: 0.7,
    frameMean: 170,
    frameLight: 0.65,
    moduleScore: moduleScore,
    portraitWellScore: portrait,
    minX: 8,
    minY: 8,
    maxX: 150,
    maxY: 90,
    touchesLeft: false,
    touchesRight: false,
    touchesTop: false,
    touchesBottom: false,
  );
}

void main() {
  group('IdDocumentClassifier type', () {
    test('matches a distinctive PhilSys word even when the title is split', () {
      expect(
        IdDocumentClassifier.classifyType(
          'pagkakakilanlan given name',
          SellerIdType.nationalId,
        ),
        IdTypeDecision.match,
      );
    });

    test('matches PhilSys copy to National ID', () {
      expect(
        IdDocumentClassifier.classifyType(
          'Republic of the Philippines Pambansang Pagkakakilanlan PhilSys',
          SellerIdType.nationalId,
        ),
        IdTypeDecision.match,
      );
    });

    test('rejects a driver license when National ID was selected', () {
      expect(
        IdDocumentClassifier.classifyType(
          'Land Transportation Office Driver s License Non Professional',
          SellerIdType.nationalId,
        ),
        IdTypeDecision.mismatch,
      );
    });

    test('treats credit-card copy as unsupported', () {
      expect(
        IdDocumentClassifier.classifyType(
          'VISA Mastercard Valid Thru 12/28',
          SellerIdType.nationalId,
        ),
        IdTypeDecision.unsupported,
      );
    });

    test('empty OCR is unknown, not a match', () {
      expect(
        IdDocumentClassifier.classifyType('', SellerIdType.nationalId),
        IdTypeDecision.unknown,
      );
    });

    test('a lone short token is not an ID type match', () {
      expect(
        IdDocumentClassifier.classifyType('lto', SellerIdType.driversLicense),
        IdTypeDecision.unknown,
      );
      expect(
        IdDocumentClassifier.classifyType('sss', SellerIdType.sssId),
        IdTypeDecision.unknown,
      );
    });

    test('UMID keywords beat a generic SSS hit', () {
      expect(
        IdDocumentClassifier.classifyType(
          'UMID Unified Multi Purpose SSS',
          SellerIdType.umidId,
        ),
        IdTypeDecision.match,
      );
      expect(
        IdDocumentClassifier.classifyType(
          'UMID Unified Multi Purpose SSS',
          SellerIdType.sssId,
        ),
        IdTypeDecision.mismatch,
      );
    });
  });

  group('IdDocumentClassifier side', () {
    test('a portrait-sized face with identity fields is FRONT', () {
      expect(
        IdDocumentClassifier.classifySide(
          text: 'given name date of birth',
          evidence: const DocumentEvidence(
            available: true,
            alphanumericChars: 24,
            blockCount: 4,
            faceCoverage: 0.12,
            faceCenterX: 0.28,
            recognizedText: 'given name date of birth',
          ),
          geometry: _card(),
          expectedType: SellerIdType.nationalId,
        ),
        IdSideDecision.front,
      );
    });

    test('PhilSys reverse demographics without a photo are BACK', () {
      expect(
        IdDocumentClassifier.classifySide(
          text:
              'sex female blood type o marital status single place of birth date issued',
          evidence: const DocumentEvidence(
            available: true,
            alphanumericChars: 40,
            blockCount: 6,
            faceCoverage: 0,
            recognizedText:
                'sex female blood type o marital status single place of birth date issued',
          ),
          geometry: _card(moduleScore: 0.4, portrait: 0.2),
          expectedType: SellerIdType.nationalId,
        ),
        IdSideDecision.back,
      );
    });

    test('left-right contrast alone is not treated as FRONT', () {
      expect(
        IdDocumentClassifier.classifySide(
          text: '',
          evidence: const DocumentEvidence(available: true),
          geometry: _card(moduleScore: 0.05, portrait: 0.4),
          expectedType: SellerIdType.nationalId,
        ),
        IdSideDecision.unknown,
      );
    });

    test('QR without reverse fields is not a live wrong-side veto', () {
      expect(
        IdDocumentClassifier.isConfidentOppositeSide(
          detected: IdSideDecision.back,
          expected: IdCaptureSide.front,
          text: 'qr code',
          expectedType: SellerIdType.nationalId,
        ),
        isFalse,
      );
      expect(
        IdDocumentClassifier.isConfidentOppositeSide(
          detected: IdSideDecision.back,
          expected: IdCaptureSide.front,
          text: 'blood type o place of birth',
          expectedType: SellerIdType.nationalId,
        ),
        isTrue,
      );
    });

    test('QR-like modules without a face are BACK', () {
      expect(
        IdDocumentClassifier.classifySide(
          text: 'this is to certify qr code',
          evidence: const DocumentEvidence(
            available: true,
            alphanumericChars: 18,
            blockCount: 3,
            faceCoverage: 0,
            recognizedText: 'this is to certify qr code',
          ),
          geometry: _card(moduleScore: 0.4, portrait: 0),
          expectedType: SellerIdType.nationalId,
        ),
        IdSideDecision.back,
      );
    });

    test('identity labels beat a front-side QR when no portrait is seen', () {
      expect(
        IdDocumentClassifier.classifySide(
          text: 'given name last name date of birth qr code',
          evidence: const DocumentEvidence(
            available: true,
            alphanumericChars: 32,
            blockCount: 5,
            faceCoverage: 0,
            recognizedText: 'given name last name date of birth qr code',
          ),
          geometry: _card(moduleScore: 0.85),
          expectedType: SellerIdType.nationalId,
        ),
        IdSideDecision.front,
      );
    });

    test('a portrait still wins when the front also prints a QR', () {
      expect(
        IdDocumentClassifier.classifySide(
          text: 'pambansang pagkakakilanlan given name qr code',
          evidence: const DocumentEvidence(
            available: true,
            alphanumericChars: 36,
            blockCount: 5,
            faceCoverage: 0.14,
            faceCenterX: 0.28,
            recognizedText: 'pambansang pagkakakilanlan given name qr code',
          ),
          geometry: _card(moduleScore: 0.85),
          expectedType: SellerIdType.nationalId,
        ),
        IdSideDecision.front,
      );
    });
  });

  group('IdDocumentClassifier.rejection', () {
    const frontId = DocumentEvidence(
      available: true,
      alphanumericChars: 28,
      blockCount: 5,
      faceCoverage: 0.12,
      faceCenterX: 0.3,
      textCoverage: 0.3,
      recognizedText:
          'pambansang pagkakakilanlan philsys given name date of birth',
    );

    test('accepts a National ID front when OCR misses the stylized title', () {
      expect(
        IdDocumentClassifier.rejection(
          evidence: const DocumentEvidence(
            available: true,
            alphanumericChars: 26,
            blockCount: 5,
            faceCoverage: 0.12,
            faceCenterX: 0.28,
            textCoverage: 0.28,
            recognizedText: 'given name last name date of birth address',
          ),
          geometry: _card(),
          expectedType: SellerIdType.nationalId,
          expectedSide: IdCaptureSide.front,
        ),
        isNull,
      );
    });

    test('accepts a matching National ID front', () {
      expect(
        IdDocumentClassifier.rejection(
          evidence: frontId,
          geometry: _card(),
          expectedType: SellerIdType.nationalId,
          expectedSide: IdCaptureSide.front,
        ),
        isNull,
      );
    });

    test('rejects PhilSys reverse when the front is required', () {
      final result = IdDocumentClassifier.rejection(
        evidence: const DocumentEvidence(
          available: true,
          alphanumericChars: 36,
          blockCount: 5,
          faceCoverage: 0,
          recognizedText:
              'blood type o marital status single place of birth date issued',
        ),
        geometry: _card(moduleScore: 0.85, portrait: 0.2),
        expectedType: SellerIdType.nationalId,
        expectedSide: IdCaptureSide.front,
      );
      expect(result!.issue, IdQualityIssue.wrongSide);
      expect(result.message, contains('front of your ID'));
    });

    test('accepts a matching National ID back', () {
      expect(
        IdDocumentClassifier.rejection(
          evidence: const DocumentEvidence(
            available: true,
            alphanumericChars: 22,
            blockCount: 3,
            faceCoverage: 0,
            textCoverage: 0.22,
            recognizedText: 'philsys this is to certify qr code',
          ),
          geometry: _card(moduleScore: 0.4, portrait: 0),
          expectedType: SellerIdType.nationalId,
          expectedSide: IdCaptureSide.back,
        ),
        isNull,
      );
    });

    test('PhilSys back without a title is allowed after a confirmed front', () {
      expect(
        IdDocumentClassifier.rejection(
          evidence: const DocumentEvidence(
            available: true,
            alphanumericChars: 28,
            blockCount: 4,
            faceCoverage: 0,
            recognizedText: 'blood type o place of birth date issued',
          ),
          geometry: _card(moduleScore: 0.85, portrait: 0),
          expectedType: SellerIdType.nationalId,
          expectedSide: IdCaptureSide.back,
          sessionTypeConfirmed: true,
        ),
        isNull,
      );
    });

    test('rejects the front while expecting the back', () {
      final result = IdDocumentClassifier.rejection(
        evidence: frontId,
        geometry: _card(),
        expectedType: SellerIdType.nationalId,
        expectedSide: IdCaptureSide.back,
      );
      expect(result, isNotNull);
      expect(result!.issue, IdQualityIssue.wrongSide);
      expect(result.message, contains('back of your ID'));
    });

    test('rejects a visa as not a supported government ID', () {
      final result = IdDocumentClassifier.rejection(
        evidence: const DocumentEvidence(
          available: true,
          alphanumericChars: 20,
          blockCount: 3,
          recognizedText: 'visa valid thru',
        ),
        geometry: _card(),
        expectedType: SellerIdType.nationalId,
        expectedSide: IdCaptureSide.front,
      );
      expect(result!.issue, IdQualityIssue.notSupportedId);
    });

    test('unknown ML Kit output is fail-closed', () {
      final result = IdDocumentClassifier.rejection(
        evidence: const DocumentEvidence.unknown(),
        geometry: _card(),
        expectedType: SellerIdType.nationalId,
        expectedSide: IdCaptureSide.front,
      );
      expect(result!.issue, IdQualityIssue.uncertain);
    });

    test('wrong selected type is rejected', () {
      final result = IdDocumentClassifier.rejection(
        evidence: frontId,
        geometry: _card(),
        expectedType: SellerIdType.passport,
        expectedSide: IdCaptureSide.front,
      );
      expect(result!.issue, IdQualityIssue.wrongIdType);
    });

    test('date of birth alone is not enough to accept an unknown type', () {
      final result = IdDocumentClassifier.rejection(
        evidence: const DocumentEvidence(
          available: true,
          alphanumericChars: 18,
          blockCount: 3,
          faceCoverage: 0.12,
          faceCenterX: 0.28,
          recognizedText: 'date of birth 01 january 1990',
        ),
        geometry: _card(),
        expectedType: SellerIdType.nationalId,
        expectedSide: IdCaptureSide.front,
      );
      expect(result!.issue, IdQualityIssue.uncertain);
    });

    test('random printed text is not treated as an ID', () {
      final result = IdDocumentClassifier.rejection(
        evidence: const DocumentEvidence(
          available: true,
          alphanumericChars: 24,
          blockCount: 4,
          recognizedText: 'composition notebook college ruled 80 sheets',
        ),
        geometry: _card(),
        expectedType: SellerIdType.nationalId,
        expectedSide: IdCaptureSide.front,
      );
      expect(result!.issue, IdQualityIssue.uncertain);
    });

    test('a driver-license reverse is rejected on the front step', () {
      final result = IdDocumentClassifier.rejection(
        evidence: const DocumentEvidence(
          available: true,
          alphanumericChars: 22,
          blockCount: 3,
          faceCoverage: 0,
          recognizedText: 'land transportation office restrictions conditions',
        ),
        geometry: _card(moduleScore: 0.4, portrait: 0),
        expectedType: SellerIdType.driversLicense,
        expectedSide: IdCaptureSide.front,
      );
      expect(result!.issue, IdQualityIssue.wrongSide);
    });
  });
}
