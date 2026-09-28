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
    test('a single PhilSys token is not enough to match National ID', () {
      expect(
        IdDocumentClassifier.classifyType(
          'pagkakakilanlan given name',
          SellerIdType.nationalId,
        ),
        IdTypeDecision.unknown,
      );
    });

    test('matches PhilSys when the header phrase is present', () {
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
      expect(result.message, contains('front of your'));
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
      expect(result.message, contains('back of your'));
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

  group('selected ID evidence', () {
    test('accepts a driver license front and rejects it as a National ID', () {
      const evidence = DocumentEvidence(
        available: true,
        alphanumericChars: 48,
        blockCount: 5,
        faceCoverage: 0.14,
        faceCenterX: 0.3,
        textCoverage: 0.32,
        recognizedText:
            'land transportation office driver s license last name date of birth',
      );
      expect(
        IdDocumentClassifier.rejection(
          evidence: evidence,
          geometry: _card(),
          expectedType: SellerIdType.driversLicense,
          expectedSide: IdCaptureSide.front,
        ),
        isNull,
      );
      final wrong = IdDocumentClassifier.rejection(
        evidence: evidence,
        geometry: _card(),
        expectedType: SellerIdType.nationalId,
        expectedSide: IdCaptureSide.front,
      );
      expect(wrong!.issue, IdQualityIssue.wrongIdType);
      expect(wrong.message, 'This does not appear to be a National ID.');
    });

    test(
      'accepts a driver license back and rejects the front on that step',
      () {
        const evidence = DocumentEvidence(
          available: true,
          alphanumericChars: 36,
          blockCount: 4,
          recognizedText: 'land transportation office restrictions conditions',
        );
        expect(
          IdDocumentClassifier.rejection(
            evidence: evidence,
            geometry: _card(moduleScore: 0.4, portrait: 0),
            expectedType: SellerIdType.driversLicense,
            expectedSide: IdCaptureSide.back,
          ),
          isNull,
        );
        expect(
          IdDocumentClassifier.rejection(
            evidence: evidence,
            geometry: _card(moduleScore: 0.4, portrait: 0),
            expectedType: SellerIdType.driversLicense,
            expectedSide: IdCaptureSide.front,
          )!.issue,
          IdQualityIssue.wrongSide,
        );
      },
    );

    test('accepts an SSS front and rejects it when UMID was selected', () {
      const evidence = DocumentEvidence(
        available: true,
        alphanumericChars: 40,
        blockCount: 5,
        faceCoverage: 0.12,
        faceCenterX: 0.26,
        recognizedText:
            'social security system ss number date of birth signature',
      );
      expect(
        IdDocumentClassifier.rejection(
          evidence: evidence,
          geometry: _card(),
          expectedType: SellerIdType.sssId,
          expectedSide: IdCaptureSide.front,
        ),
        isNull,
      );
      expect(
        IdDocumentClassifier.rejection(
          evidence: evidence,
          geometry: _card(),
          expectedType: SellerIdType.umidId,
          expectedSide: IdCaptureSide.front,
        )!.issue,
        IdQualityIssue.wrongIdType,
      );
    });

    test(
      'accepts a UMID front only when more than the word UMID is present',
      () {
        expect(
          IdDocumentClassifier.rejection(
            evidence: const DocumentEvidence(
              available: true,
              alphanumericChars: 36,
              blockCount: 4,
              faceCoverage: 0.13,
              faceCenterX: 0.28,
              recognizedText: 'unified multi purpose id crn',
            ),
            geometry: _card(),
            expectedType: SellerIdType.umidId,
            expectedSide: IdCaptureSide.front,
          ),
          isNull,
        );
        final lone = IdDocumentClassifier.rejection(
          evidence: const DocumentEvidence(
            available: true,
            alphanumericChars: 4,
            blockCount: 1,
            faceCoverage: 0.13,
            faceCenterX: 0.28,
            recognizedText: 'umid',
          ),
          geometry: _card(),
          expectedType: SellerIdType.umidId,
          expectedSide: IdCaptureSide.front,
        );
        expect(lone, isNotNull);
        expect(lone!.passed, isFalse);
      },
    );

    test('accepts a passport photo page from the machine-readable zone', () {
      expect(
        IdDocumentClassifier.rejection(
          evidence: const DocumentEvidence(
            available: true,
            alphanumericChars: 44,
            blockCount: 3,
            faceCoverage: 0.16,
            faceCenterX: 0.22,
            recognizedText: 'P<PHLDOE<<JUAN<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<',
          ),
          geometry: _card(portrait: 0.2),
          expectedType: SellerIdType.passport,
          expectedSide: IdCaptureSide.front,
        ),
        isNull,
      );
    });

    test('rejects a driver license when a passport was selected', () {
      final result = IdDocumentClassifier.rejection(
        evidence: const DocumentEvidence(
          available: true,
          alphanumericChars: 40,
          blockCount: 4,
          faceCoverage: 0.12,
          faceCenterX: 0.3,
          recognizedText:
              'land transportation office driver s license last name date of birth',
        ),
        geometry: _card(),
        expectedType: SellerIdType.passport,
        expectedSide: IdCaptureSide.front,
      );
      expect(result!.issue, IdQualityIssue.wrongIdType);
    });

    test(
      'a different ID on the back is rejected after the front was confirmed',
      () {
        final result = IdDocumentClassifier.rejection(
          evidence: const DocumentEvidence(
            available: true,
            alphanumericChars: 48,
            blockCount: 5,
            faceCoverage: 0.14,
            faceCenterX: 0.3,
            textCoverage: 0.32,
            recognizedText:
                'land transportation office driver s license last name date of birth',
          ),
          geometry: _card(),
          expectedType: SellerIdType.nationalId,
          expectedSide: IdCaptureSide.back,
          sessionTypeConfirmed: true,
        );
        expect(result!.issue, IdQualityIssue.wrongIdType);
      },
    );

    test('a face outside the portrait zone does not confirm a National ID', () {
      final result = IdDocumentClassifier.rejection(
        evidence: const DocumentEvidence(
          available: true,
          alphanumericChars: 32,
          blockCount: 4,
          faceCoverage: 0.2,
          faceCenterX: 0.9,
          recognizedText: 'given name last name date of birth',
        ),
        geometry: _card(),
        expectedType: SellerIdType.nationalId,
        expectedSide: IdCaptureSide.front,
      );
      expect(result, isNotNull);
    });

    test(
      'text outside the decision is ignored because only crop text is passed',
      () {
        final result = IdDocumentClassifier.rejection(
          evidence: const DocumentEvidence(
            available: true,
            alphanumericChars: 8,
            blockCount: 1,
            recognizedText: 'logitech',
          ),
          geometry: _card(),
          expectedType: SellerIdType.driversLicense,
          expectedSide: IdCaptureSide.front,
        );
        expect(result, isNotNull);
        expect(result!.issue, isNot(IdQualityIssue.wrongIdType));
      },
    );

    test('a screen address is not accepted as the selected ID', () {
      final result = IdDocumentClassifier.rejection(
        evidence: const DocumentEvidence(
          available: true,
          alphanumericChars: 52,
          blockCount: 6,
          textCoverage: 0.4,
          recognizedText: 'https://www.example.com drivers license last name',
        ),
        geometry: _card(),
        expectedType: SellerIdType.driversLicense,
        expectedSide: IdCaptureSide.front,
      );
      expect(result!.issue, IdQualityIssue.notId);
      expect(result.message, contains('screen'));
    });

    test('blur is not skipped when the selected ID text is present', () {
      final result = IdDocumentClassifier.apply(
        quality: IdQualityResult.fail(IdQualityIssue.blurry),
        evidence: const DocumentEvidence(
          available: true,
          alphanumericChars: 40,
          blockCount: 4,
          faceCoverage: 0.12,
          faceCenterX: 0.3,
          recognizedText: 'pambansang pagkakakilanlan given name date of birth',
        ),
        geometry: _card(),
        expectedType: SellerIdType.nationalId,
        expectedSide: IdCaptureSide.front,
      );
      expect(result.issue, IdQualityIssue.blurry);
    });

    test('live preview stays invalid until the selected ID is recognized', () {
      final luma = LiveIdAssessment(
        status: LiveIdStatus.aligned,
        occupancy: 0.72,
        geometry: _card(),
      );
      expect(
        IdDocumentClassifier.confirmLive(
          luma: luma,
          evidence: const DocumentEvidence.unknown(),
          expectedType: SellerIdType.driversLicense,
          expectedSide: IdCaptureSide.front,
        ).isAligned,
        isFalse,
      );
      final wrong = IdDocumentClassifier.confirmLive(
        luma: luma,
        evidence: const DocumentEvidence(
          available: true,
          alphanumericChars: 40,
          blockCount: 4,
          faceCoverage: 0.12,
          faceCenterX: 0.28,
          recognizedText: 'pambansang pagkakakilanlan given name date of birth',
        ),
        expectedType: SellerIdType.driversLicense,
        expectedSide: IdCaptureSide.front,
      );
      expect(wrong.isAligned, isFalse);
      expect(wrong.message, contains("Driver's License"));
    });

    test(
      'live preview can accept the selected front after several signals agree',
      () {
        final luma = LiveIdAssessment(
          status: LiveIdStatus.aligned,
          occupancy: 0.72,
          geometry: _card(),
        );
        final accepted = IdDocumentClassifier.confirmLive(
          luma: luma,
          evidence: const DocumentEvidence(
            available: true,
            alphanumericChars: 40,
            blockCount: 5,
            faceCoverage: 0.12,
            faceCenterX: 0.28,
            recognizedText:
                'pambansang pagkakakilanlan given name last name date of birth',
          ),
          expectedType: SellerIdType.nationalId,
          expectedSide: IdCaptureSide.front,
        );
        expect(accepted.isAligned, isTrue);
        expect(accepted.message, contains('Hold your National ID'));
      },
    );

    test(
      'each call is independent, so a retake cannot reuse the last decision',
      () {
        const national = DocumentEvidence(
          available: true,
          alphanumericChars: 40,
          blockCount: 5,
          faceCoverage: 0.12,
          faceCenterX: 0.28,
          recognizedText: 'pambansang pagkakakilanlan given name date of birth',
        );
        expect(
          IdDocumentClassifier.rejection(
            evidence: national,
            geometry: _card(),
            expectedType: SellerIdType.nationalId,
            expectedSide: IdCaptureSide.front,
          ),
          isNull,
        );
        expect(
          IdDocumentClassifier.rejection(
            evidence: const DocumentEvidence(
              available: true,
              alphanumericChars: 12,
              blockCount: 1,
              recognizedText: 'mouse',
            ),
            geometry: _card(),
            expectedType: SellerIdType.nationalId,
            expectedSide: IdCaptureSide.front,
          ),
          isNotNull,
        );
      },
    );
  });

  group('Digital National ID', () {
    const digitalFront = DocumentEvidence(
      available: true,
      alphanumericChars: 64,
      blockCount: 6,
      faceCoverage: 0.14,
      faceCenterX: 0.28,
      textCoverage: 0.55,
      recognizedText:
          'digital national id last name given name date of birth present address qr code',
    );

    test('accepts a front profile when several signals agree', () {
      expect(
        IdDocumentClassifier.rejection(
          evidence: digitalFront,
          geometry: _card(moduleScore: 0.45),
          expectedType: SellerIdType.digitalNationalId,
          expectedSide: IdCaptureSide.front,
        ),
        isNull,
      );
    });

    test('still accepts that profile when the frame is filled with text', () {
      expect(
        IdDocumentClassifier.rejection(
          evidence: const DocumentEvidence(
            available: true,
            alphanumericChars: 64,
            blockCount: 6,
            faceCoverage: 0.14,
            faceCenterX: 0.28,
            textCoverage: 0.9,
            recognizedText:
                'digital national id last name given name date of birth present address qr code',
          ),
          geometry: _card(moduleScore: 0.45),
          expectedType: SellerIdType.digitalNationalId,
          expectedSide: IdCaptureSide.front,
        ),
        isNull,
      );
    });

    test('accepts the back profile and rejects it on the front step', () {
      const back = DocumentEvidence(
        available: true,
        alphanumericChars: 40,
        blockCount: 4,
        recognizedText: 'blood type marital status qr code',
      );
      expect(
        IdDocumentClassifier.rejection(
          evidence: back,
          geometry: _card(moduleScore: 0.85, portrait: 0),
          expectedType: SellerIdType.digitalNationalId,
          expectedSide: IdCaptureSide.back,
        ),
        isNull,
      );
      expect(
        IdDocumentClassifier.rejection(
          evidence: back,
          geometry: _card(moduleScore: 0.85, portrait: 0),
          expectedType: SellerIdType.digitalNationalId,
          expectedSide: IdCaptureSide.front,
        )!.issue,
        IdQualityIssue.wrongSide,
      );
    });

    // OCR of the eGov app card. The photo is small, so face coverage is low.
    const eGovFront = DocumentEvidence(
      available: true,
      alphanumericChars: 260,
      blockCount: 14,
      faceCoverage: 0.025,
      faceCenterX: 0.22,
      textCoverage: 0.7,
      recognizedText:
          'republika ng pilipinas republic of the philippines '
          'pambansang pagkakakilanlan philippine national id '
          '6508-1451-3293-8023 apelyido/last name ramos '
          'mga pangalan/given names dexter gitnang apelyido/middle name '
          'boniol petsa ng kapanganakan/date of birth november 17, 2004 '
          'tirahan/address ph 3, mexico st, doña asuncion vill., '
          'city of davao, davao del sur, philippines, 8000 '
          'digital id number qir683 phl',
    );
    const eGovBack = DocumentEvidence(
      available: true,
      alphanumericChars: 120,
      blockCount: 8,
      textCoverage: 0.3,
      recognizedText:
          'kasarian/sex male uri ng dugo/blood type unknown '
          'kalagayang sibil/marital status single '
          'lugar ng kapanganakan/place of birth city of davao, davao del sur',
    );

    test('accepts the eGov app front with its small photo', () {
      expect(
        IdDocumentClassifier.rejection(
          evidence: eGovFront,
          geometry: _card(moduleScore: 0.5),
          expectedType: SellerIdType.digitalNationalId,
          expectedSide: IdCaptureSide.front,
        ),
        isNull,
      );
    });

    test('accepts the eGov front when the tiny digital ID label is missed', () {
      final text = eGovFront.recognizedText.replaceAll('digital id number', '');
      expect(
        IdDocumentClassifier.rejection(
          evidence: DocumentEvidence(
            available: true,
            alphanumericChars: 240,
            blockCount: 13,
            faceCoverage: 0.025,
            faceCenterX: 0.22,
            recognizedText: text,
          ),
          geometry: _card(moduleScore: 0.5),
          expectedType: SellerIdType.digitalNationalId,
          expectedSide: IdCaptureSide.front,
        ),
        isNull,
      );
    });

    test('accepts the eGov front when OCR misses the photo', () {
      expect(
        IdDocumentClassifier.rejection(
          evidence: DocumentEvidence(
            available: true,
            alphanumericChars: 260,
            blockCount: 14,
            recognizedText: eGovFront.recognizedText,
          ),
          geometry: _card(moduleScore: 0.5),
          expectedType: SellerIdType.digitalNationalId,
          expectedSide: IdCaptureSide.front,
        ),
        isNull,
      );
    });

    test('reads "lD" as "ID" in the Philippine National ID header', () {
      expect(
        IdDocumentClassifier.classifyType(
          'pambansang pagkakakilanlan philippine national lD',
          SellerIdType.digitalNationalId,
        ),
        IdTypeDecision.match,
      );
    });

    test('accepts the eGov back, which also prints the place of birth', () {
      expect(
        IdDocumentClassifier.rejection(
          evidence: eGovBack,
          geometry: _card(moduleScore: 0.6, portrait: 0),
          expectedType: SellerIdType.digitalNationalId,
          expectedSide: IdCaptureSide.back,
          sessionTypeConfirmed: true,
        ),
        isNull,
      );
    });

    test('the eGov front is the wrong side on the back step', () {
      expect(
        IdDocumentClassifier.rejection(
          evidence: eGovFront,
          geometry: _card(moduleScore: 0.5),
          expectedType: SellerIdType.digitalNationalId,
          expectedSide: IdCaptureSide.back,
          sessionTypeConfirmed: true,
        )!.issue,
        IdQualityIssue.wrongSide,
      );
    });

    test('the eGov back is the wrong side on the front step', () {
      expect(
        IdDocumentClassifier.rejection(
          evidence: eGovBack,
          geometry: _card(moduleScore: 0.6, portrait: 0),
          expectedType: SellerIdType.digitalNationalId,
          expectedSide: IdCaptureSide.front,
        )!.issue,
        IdQualityIssue.wrongSide,
      );
    });

    test('a physical PhilID back is not accepted as the digital back', () {
      expect(
        IdDocumentClassifier.rejection(
          evidence: const DocumentEvidence(
            available: true,
            alphanumericChars: 120,
            blockCount: 8,
            recognizedText:
                'sex male blood type o+ marital status single '
                'place of birth city of davao date of issue 01 jan 2023',
          ),
          geometry: _card(moduleScore: 0.6, portrait: 0),
          expectedType: SellerIdType.digitalNationalId,
          expectedSide: IdCaptureSide.back,
          sessionTypeConfirmed: true,
        ),
        isNotNull,
      );
    });

    test('live preview accepts the eGov front from the header and photo', () {
      final live = IdDocumentClassifier.confirmLive(
        luma: LiveIdAssessment(
          status: LiveIdStatus.aligned,
          occupancy: 0.7,
          geometry: _card(moduleScore: 0.5),
        ),
        evidence: const DocumentEvidence(
          available: true,
          alphanumericChars: 60,
          blockCount: 4,
          faceCoverage: 0.02,
          faceCenterX: 0.22,
          recognizedText:
              'republika ng pilipinas pambansang pagkakakilanlan ramos dexter',
        ),
        expectedType: SellerIdType.digitalNationalId,
        expectedSide: IdCaptureSide.front,
      );
      expect(live.isAligned, isTrue);
    });

    test('a gallery screenshot label does not block the digital ID', () {
      expect(
        IdDocumentClassifier.rejection(
          evidence: DocumentEvidence(
            available: true,
            alphanumericChars: 270,
            blockCount: 15,
            faceCoverage: 0.025,
            faceCenterX: 0.22,
            recognizedText:
                'screenshot_20260928-021700 ${eGovFront.recognizedText}',
          ),
          geometry: _card(moduleScore: 0.5),
          expectedType: SellerIdType.digitalNationalId,
          expectedSide: IdCaptureSide.front,
        ),
        isNull,
      );
    });

    test('guide rect follows the frame through quarter turns', () {
      const rect = OverlayNormRect(
        left: 0.1,
        top: 0.2,
        right: 0.5,
        bottom: 0.4,
      );
      final once = rect.rotatedClockwise(1);
      expect(once.left, closeTo(0.6, 1e-9));
      expect(once.top, closeTo(0.1, 1e-9));
      expect(once.right, closeTo(0.8, 1e-9));
      expect(once.bottom, closeTo(0.5, 1e-9));
      final back = rect.rotatedClockwise(4);
      expect(back.left, rect.left);
      expect(back.bottom, rect.bottom);
    });

    test('a physical National ID is not accepted as the digital ID', () {
      final result = IdDocumentClassifier.rejection(
        evidence: const DocumentEvidence(
          available: true,
          alphanumericChars: 40,
          blockCount: 5,
          faceCoverage: 0.12,
          faceCenterX: 0.28,
          recognizedText: 'pambansang pagkakakilanlan given name date of birth',
        ),
        geometry: _card(),
        expectedType: SellerIdType.digitalNationalId,
        expectedSide: IdCaptureSide.front,
      );
      expect(result!.issue, IdQualityIssue.wrongIdType);
      expect(
        result.message,
        'This does not appear to be a Digital National ID.',
      );
    });

    test('a Digital National ID is not accepted as the physical card', () {
      final result = IdDocumentClassifier.rejection(
        evidence: digitalFront,
        geometry: _card(),
        expectedType: SellerIdType.nationalId,
        expectedSide: IdCaptureSide.front,
      );
      expect(result!.issue, IdQualityIssue.wrongIdType);
    });

    test(
      'a Digital National ID on a full screen is still rejected for the physical card',
      () {
        final result = IdDocumentClassifier.rejection(
          evidence: const DocumentEvidence(
            available: true,
            alphanumericChars: 64,
            blockCount: 6,
            faceCoverage: 0.14,
            faceCenterX: 0.28,
            textCoverage: 0.92,
            recognizedText:
                'digital national id last name given name date of birth present address qr code',
          ),
          geometry: _card(),
          expectedType: SellerIdType.nationalId,
          expectedSide: IdCaptureSide.front,
        );
        expect(result!.issue, IdQualityIssue.notId);
        expect(result.message, contains('screen'));
      },
    );

    test('the digital label alone is not enough', () {
      final result = IdDocumentClassifier.rejection(
        evidence: const DocumentEvidence(
          available: true,
          alphanumericChars: 20,
          blockCount: 2,
          recognizedText: 'digital national id',
        ),
        geometry: _card(),
        expectedType: SellerIdType.digitalNationalId,
        expectedSide: IdCaptureSide.front,
      );
      expect(result, isNotNull);
      expect(result!.passed, isFalse);
    });

    test('a QR code alone is not enough', () {
      final result = IdDocumentClassifier.rejection(
        evidence: const DocumentEvidence(
          available: true,
          alphanumericChars: 8,
          blockCount: 1,
          recognizedText: 'qr code',
        ),
        geometry: _card(moduleScore: 0.9, portrait: 0),
        expectedType: SellerIdType.digitalNationalId,
        expectedSide: IdCaptureSide.front,
      );
      expect(result, isNotNull);
    });

    test('image search and social posts are rejected', () {
      final search = IdDocumentClassifier.rejection(
        evidence: const DocumentEvidence(
          available: true,
          alphanumericChars: 48,
          blockCount: 5,
          recognizedText: 'google images national id philippines digital id',
        ),
        geometry: _card(),
        expectedType: SellerIdType.digitalNationalId,
        expectedSide: IdCaptureSide.front,
      );
      expect(search!.passed, isFalse);
      expect(search.message, 'Show your Digital National ID.');

      final post = IdDocumentClassifier.rejection(
        evidence: const DocumentEvidence(
          available: true,
          alphanumericChars: 48,
          blockCount: 5,
          faceCoverage: 0.14,
          faceCenterX: 0.28,
          recognizedText:
              'facebook digital national id last name date of birth qr code',
        ),
        geometry: _card(),
        expectedType: SellerIdType.digitalNationalId,
        expectedSide: IdCaptureSide.front,
      );
      expect(post!.message, 'Show your Digital National ID.');
    });

    test('a physical license photo of a screen is still rejected', () {
      final result = IdDocumentClassifier.rejection(
        evidence: const DocumentEvidence(
          available: true,
          alphanumericChars: 40,
          blockCount: 4,
          textCoverage: 0.4,
          recognizedText: 'https://www.example.com drivers license',
        ),
        geometry: _card(),
        expectedType: SellerIdType.driversLicense,
        expectedSide: IdCaptureSide.front,
      );
      expect(result!.issue, IdQualityIssue.notId);
      expect(result.message, contains('screen'));
    });

    test('blur still fails when the digital profile text is present', () {
      final result = IdDocumentClassifier.apply(
        quality: IdQualityResult.fail(IdQualityIssue.blurry),
        evidence: digitalFront,
        geometry: _card(),
        expectedType: SellerIdType.digitalNationalId,
        expectedSide: IdCaptureSide.front,
      );
      expect(result.issue, IdQualityIssue.blurry);
    });
  });

  test('passport guide is taller than an ID-1 card guide', () {
    final card = IdImageMetrics.centerCardWindow(1080, 1920);
    final passport = IdImageMetrics.centerCardWindow(
      1080,
      1920,
      aspect: IdCaptureGuide.aspectFor(SellerIdType.passport),
    );
    expect(card.width / card.height, closeTo(IdCaptureGuide.cardAspect, 0.08));
    expect(
      passport.width / passport.height,
      closeTo(IdCaptureGuide.passportPageAspect, 0.08),
    );
    final outside = IdImageMetrics.guideOverlay(width: 1000, height: 1000);
    expect(
      outside.includesBlock(left: 0.0, top: 0.0, right: 0.05, bottom: 0.05),
      isFalse,
    );
  });
}
