import 'package:flutter/foundation.dart';

import 'id_image_quality.dart';
import 'seller_id_type.dart';

/// Requested ID face during Become a Seller capture.
enum IdCaptureSide { front, back }

enum IdTypeDecision { match, mismatch, unknown, unsupported }

enum IdSideDecision { front, back, unknown }

/// OCR + face + QR-module classification for seller ID captures.
///
/// There is no on-device ID object-detection model. Side is inferred from
/// document features of the five accepted Philippine IDs — never from which
/// capture screen is open.
class IdDocumentClassifier {
  const IdDocumentClassifier._();

  static String normalize(String raw) {
    final lower = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ');
    return lower.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String wrongSideMessage(IdCaptureSide expected) =>
      expected == IdCaptureSide.back
      ? 'Wrong side detected. Please capture the back of your ID.'
      : 'Wrong side detected. Please capture the front of your ID.';

  /// Live veto only. QR-only "back" is too weak — digital PhilID fronts print a QR.
  static bool isConfidentOppositeSide({
    required IdSideDecision detected,
    required IdCaptureSide expected,
    required String text,
    required SellerIdType expectedType,
  }) {
    final opposite = expected == IdCaptureSide.front
        ? IdSideDecision.back
        : IdSideDecision.front;
    if (detected != opposite) return false;
    if (detected == IdSideDecision.back) {
      return _termHits(normalize(text), _backTermsFor(expectedType)) >= 1;
    }
    return true;
  }

  /// Returns a failing [IdQualityResult] when the still must not be accepted.
  ///
  /// [sessionTypeConfirmed] is true after a validated front of [expectedType]
  /// in this session. PhilSys / UMID backs often omit the title line.
  static IdQualityResult? rejection({
    required DocumentEvidence evidence,
    required IdDocumentGeometry geometry,
    required SellerIdType expectedType,
    required IdCaptureSide expectedSide,
    bool sessionTypeConfirmed = false,
  }) {
    if (!evidence.available) {
      _trace('reject uncertain: ML Kit unavailable');
      return IdQualityResult.fail(IdQualityIssue.uncertain);
    }

    final text = normalize(evidence.recognizedText);
    if (evidence.looksLikePaymentCard || isUnsupportedDocument(text)) {
      _trace('reject unsupported object type=$expectedType side=$expectedSide');
      return IdQualityResult.fail(IdQualityIssue.notSupportedId);
    }
    if (evidence.isConfidentNonDocument) {
      _trace('reject non-document (screen/selfie)');
      return IdQualityResult.fail(IdQualityIssue.notId);
    }

    final type = classifyType(text, expectedType);
    final side = classifySide(
      text: text,
      evidence: evidence,
      geometry: geometry,
      expectedType: expectedType,
    );

    _trace(
      'expectedSide=$expectedSide detectedSide=$side '
      'detectedObject=${type.name} idType=${expectedType.storageValue} '
      'face=${evidence.faceCoverage.toStringAsFixed(2)} '
      'faceX=${evidence.faceCenterX?.toStringAsFixed(2)} '
      'module=${geometry.moduleScore.toStringAsFixed(2)} '
      'ocrChars=${evidence.alphanumericChars} '
      'ocr="${text.length > 80 ? text.substring(0, 80) : text}"',
    );

    if (type == IdTypeDecision.unsupported) {
      return IdQualityResult.fail(IdQualityIssue.notSupportedId);
    }
    if (type == IdTypeDecision.mismatch) {
      return IdQualityResult.fail(
        IdQualityIssue.wrongIdType,
        message:
            'This photo does not match the selected ID type. '
            'Please capture your ${expectedType.label}.',
      );
    }

    if (side == IdSideDecision.unknown) {
      return IdQualityResult.fail(IdQualityIssue.uncertain);
    }
    final expected = expectedSide == IdCaptureSide.front
        ? IdSideDecision.front
        : IdSideDecision.back;
    if (side != expected) {
      return IdQualityResult.fail(
        IdQualityIssue.wrongSide,
        message: wrongSideMessage(expectedSide),
      );
    }

    final typeOk =
        type == IdTypeDecision.match ||
        (sessionTypeConfirmed &&
            expectedSide == IdCaptureSide.back &&
            type == IdTypeDecision.unknown) ||
        (type == IdTypeDecision.unknown &&
            _layoutSupportsSelected(
              expectedType: expectedType,
              expectedSide: expectedSide,
              text: text,
              evidence: evidence,
            ));
    if (!typeOk) {
      return IdQualityResult.fail(IdQualityIssue.uncertain);
    }
    _trace('accept type=${expectedType.storageValue} side=$expectedSide');
    return null;
  }

  static IdTypeDecision classifyType(String text, SellerIdType expected) {
    final normalized = normalize(text);
    if (normalized.isEmpty) return IdTypeDecision.unknown;
    if (isUnsupportedDocument(normalized)) {
      return IdTypeDecision.unsupported;
    }

    final scores = <SellerIdType, int>{
      for (final type in SellerIdType.values)
        type: _typeScore(normalized, type),
    };
    if (scores[SellerIdType.umidId]! > 0) {
      scores[SellerIdType.sssId] = 0;
    }
    final expectedScore = scores[expected] ?? 0;
    var bestType = expected;
    var bestScore = expectedScore;
    var tied = false;
    for (final entry in scores.entries) {
      if (entry.value > bestScore) {
        bestType = entry.key;
        bestScore = entry.value;
        tied = false;
      } else if (entry.value == bestScore &&
          entry.value > 0 &&
          entry.key != bestType) {
        tied = true;
      }
    }

    if (bestScore == 0 && expectedScore == 0) {
      return IdTypeDecision.unknown;
    }
    if (expectedScore == 0 && bestScore > 0) {
      return IdTypeDecision.mismatch;
    }
    if (tied && bestScore == expectedScore) {
      return IdTypeDecision.unknown;
    }
    if (bestType != expected) {
      return IdTypeDecision.mismatch;
    }
    return IdTypeDecision.match;
  }

  /// Independent of [expectedSide]. Never infers side from the capture step.
  static IdSideDecision classifySide({
    required String text,
    required DocumentEvidence evidence,
    required IdDocumentGeometry geometry,
    required SellerIdType expectedType,
  }) {
    final normalized = normalize(text);
    final portrait = _hasIdPortrait(evidence);
    final machineCode = _hasMachineCode(geometry, normalized);
    final frontFields = _termHits(normalized, _frontIdentityTerms);
    final reverseFields = _termHits(normalized, _backTermsFor(expectedType));

    // Portrait is the front discriminator. Digital PhilIDs print a QR on the
    // photo side, so QR/barcode labels must not override a real ID photo.
    // Reverse-only demographics (blood type, restrictions, …) still win.
    if (portrait && reverseFields == 0) {
      return IdSideDecision.front;
    }
    if (portrait && frontFields > 0 && reverseFields < 2) {
      return IdSideDecision.front;
    }

    // Name + DOB on the photo side, even if a QR is also printed (ePhilID).
    if (frontFields >= 2 && reverseFields == 0) {
      return IdSideDecision.front;
    }

    // Physical backs: reverse-only fields, or a QR with no identity labels.
    if (!portrait && reverseFields >= 1) {
      return IdSideDecision.back;
    }
    if (!portrait && machineCode && frontFields == 0) {
      return IdSideDecision.back;
    }

    if (portrait && reverseFields >= 2) {
      return IdSideDecision.back;
    }

    return IdSideDecision.unknown;
  }

  @visibleForTesting
  static bool isUnsupportedDocument(String text) {
    final normalized = normalize(text);
    if (normalized.isEmpty) return false;
    return _termHits(normalized, _unsupportedTerms) > 0;
  }

  /// Title OCR often misses stylized PhilSys / LTO headers. A selected type
  /// may still be confirmed from exclusive field labels on that document.
  /// This is not "the capture step is front, so accept".
  static bool _layoutSupportsSelected({
    required SellerIdType expectedType,
    required IdCaptureSide expectedSide,
    required String text,
    required DocumentEvidence evidence,
  }) {
    switch (expectedType) {
      case SellerIdType.nationalId:
        if (expectedSide != IdCaptureSide.front) return false;
        // Physical / digital PhilID photo side. The wordmark is a logo;
        // ML Kit reliably reads the field labels instead.
        final identity =
            _hasTerm(text, 'given name') ||
            _hasTerm(text, 'last name') ||
            _hasTerm(text, 'surname');
        return identity && _hasTerm(text, 'date of birth');
      case SellerIdType.driversLicense:
        if (expectedSide != IdCaptureSide.front) return false;
        return _hasIdPortrait(evidence) &&
            _hasTerm(text, 'date of birth') &&
            (_hasTerm(text, 'last name') || _hasTerm(text, 'given name')) &&
            (_hasTerm(text, 'license') ||
                _hasTerm(text, 'lto') ||
                _hasTerm(text, 'non professional') ||
                _hasTerm(text, 'nonprofessional'));
      case SellerIdType.passport:
      case SellerIdType.sssId:
      case SellerIdType.umidId:
        return false;
    }
  }

  static bool _hasIdPortrait(DocumentEvidence evidence) {
    final face = evidence.faceCoverage;
    if (face < IdImageMetrics.minFrontFaceCoverage ||
        face > IdImageMetrics.maxFrontFaceCoverage) {
      return false;
    }
    final x = evidence.faceCenterX;
    if (x != null && x > 0.62) {
      // PH ID portraits sit on the left/center, not the far right QR panel.
      return false;
    }
    return true;
  }

  static bool _hasMachineCode(IdDocumentGeometry geometry, String text) {
    if (_hasTerm(text, 'qr code') || _hasTerm(text, 'barcode')) return true;
    // Ordinary ID text bands land ~0.24–0.75. Only a dense checkerboard is
    // treated as a QR when OCR did not read "QR".
    return geometry.moduleScore >= IdImageMetrics.denseQrModuleScore;
  }

  static int _typeScore(String text, SellerIdType type) {
    var hits = _termHits(text, _typeTerms[type]!);
    // Short tokens are too noisy unless another phrase for that type hit.
    if (hits == 1 && _onlyShortToken(text, type)) return 0;
    return hits;
  }

  static bool _onlyShortToken(String text, SellerIdType type) {
    const short = ['lto', 'sss', 'dfa'];
    var shortHits = 0;
    var longHits = 0;
    for (final term in _typeTerms[type]!) {
      if (!_hasTerm(text, term)) continue;
      if (short.contains(term)) {
        shortHits++;
      } else {
        longHits++;
      }
    }
    return shortHits > 0 && longHits == 0;
  }

  static List<String> _backTermsFor(SellerIdType type) => switch (type) {
    SellerIdType.nationalId => _nationalIdBackTerms,
    SellerIdType.driversLicense => _driversBackTerms,
    SellerIdType.passport => _passportBackTerms,
    SellerIdType.sssId => _sssBackTerms,
    SellerIdType.umidId => _umidBackTerms,
  };

  static int _termHits(String text, List<String> terms) {
    var hits = 0;
    for (final term in terms) {
      if (_hasTerm(text, term)) hits++;
    }
    return hits;
  }

  static bool _hasTerm(String text, String term) {
    if (term.contains(' ')) return text.contains(term);
    return RegExp('\\b${RegExp.escape(term)}\\b').hasMatch(text);
  }

  static void _trace(String message) {
    if (kDebugMode) {
      debugPrint('ID_CAPTURE $message');
    }
  }

  static const Map<SellerIdType, List<String>> _typeTerms = {
    SellerIdType.nationalId: [
      'philsys',
      'phil sys',
      'philippine identification',
      'philippine identification card',
      'pambansang pagkakakilanlan',
      'pambansangpagkakakilanlan',
      'pagkakakilanlan',
      'pambansang',
      'national id',
      'national identification',
      'philippine identification system',
      'philsys card',
      'philsys number',
    ],
    SellerIdType.driversLicense: [
      'drivers license',
      'driver license',
      'driver s license',
      'land transportation office',
      'land transportation',
      'non professional',
      'nonprofessional',
      'lto',
    ],
    SellerIdType.passport: [
      'passport',
      'pasaporte',
      'department of foreign affairs',
      'dfa',
    ],
    SellerIdType.sssId: [
      'social security system',
      'sss id',
      'ss number',
      'sss no',
      'sss',
    ],
    SellerIdType.umidId: [
      'umid',
      'unified multi purpose',
      'unified multipurpose',
      'gsis umid',
    ],
  };

  /// Fields that appear on the photo side, not on PhilSys reverse demographics.
  static const List<String> _frontIdentityTerms = [
    'given name',
    'given names',
    'last name',
    'surname',
    'date of birth',
    'pambansang pagkakakilanlan',
    'drivers license',
    'driver s license',
    'passport',
    'present address',
  ];

  /// PSA: PhilID reverse has sex, blood type, marital status, place of birth,
  /// date of issue, QR, and barcode — not the portrait block.
  static const List<String> _nationalIdBackTerms = [
    'blood type',
    'marital status',
    'place of birth',
    'date issued',
    'date of issue',
    'this is to certify',
  ];

  static const List<String> _driversBackTerms = [
    'restrictions',
    'conditions',
    'this card',
  ];

  static const List<String> _passportBackTerms = [
    'observations',
    'amendments',
    'endorsements',
  ];

  static const List<String> _sssBackTerms = [
    'signature of',
    'in case of emergency',
    'this card',
  ];

  static const List<String> _umidBackTerms = [
    'this is to certify',
    'in case of emergency',
  ];

  static const List<String> _unsupportedTerms = [
    'visa',
    'mastercard',
    'master card',
    'american express',
    'amex',
    'unionpay',
    'valid thru',
    'debit card',
    'credit card',
    'student id',
    'philhealth',
    'voter s id',
    'voters id',
    'voter id',
  ];
}
