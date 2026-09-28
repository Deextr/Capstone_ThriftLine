import 'package:flutter/foundation.dart';

import 'id_image_quality.dart';
import 'seller_id_type.dart';

/// Requested ID face during Become a Seller capture.
enum IdCaptureSide { front, back }

enum IdTypeDecision { match, mismatch, unknown, unsupported }

enum IdSideDecision { front, back, unknown }

/// OCR + face + geometry classification for the selected seller ID.
///
/// There is no on-device ID object-detection model. A capture is accepted
/// only when document shape, the selected ID, the expected side, and image
/// quality agree. This does not prove the document is authentic.
class IdDocumentClassifier {
  const IdDocumentClassifier._();

  /// One distinctive phrase is not enough. Two weak hits, or one strong
  /// phrase, are required before a type is treated as recognized.
  @visibleForTesting
  static const int typeMatchThreshold = 2;

  static String normalize(String raw) {
    final lower = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ');
    // OCR commonly reads the "I" of a standalone "ID" as "l" or "1".
    return lower
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\b[l1]d\b'), 'id')
        .trim();
  }

  static String wrongSideMessage(
    IdCaptureSide expected,
    SellerIdType expectedType,
  ) {
    if (expectedType == SellerIdType.passport) {
      return expected == IdCaptureSide.back
          ? 'Show the page opposite your passport photo.'
          : 'Show the photo page of your passport.';
    }
    return expected == IdCaptureSide.back
        ? 'Show the back of your ${expectedType.label}.'
        : 'Show the front of your ${expectedType.label}.';
  }

  static String wrongTypeMessage(SellerIdType expectedType) =>
      'This does not appear to be a ${expectedType.label}.';

  static String notDetectedMessage(SellerIdType expectedType) =>
      expectedType == SellerIdType.digitalNationalId
      ? 'We can\'t recognize a Digital National ID. Turn the phone '
            'sideways so the ID fills the frame.'
      : 'We can\'t detect your ${expectedType.label}.';

  /// Keeps a passing quality result only when the still matches [expectedType]
  /// and [expectedSide]. Blur, glare, and framing failures are left as-is.
  static IdQualityResult apply({
    required IdQualityResult quality,
    required DocumentEvidence evidence,
    required IdDocumentGeometry geometry,
    required SellerIdType expectedType,
    required IdCaptureSide expectedSide,
    bool sessionTypeConfirmed = false,
  }) {
    if (!quality.passed) return quality;
    return rejection(
          evidence: evidence,
          geometry: geometry,
          expectedType: expectedType,
          expectedSide: expectedSide,
          sessionTypeConfirmed: sessionTypeConfirmed,
        ) ??
        quality;
  }

  /// Live gate. Geometry can open the check; it cannot turn the frame valid.
  ///
  /// Preview frames are low resolution, so small Digital National ID labels
  /// often do not OCR. That type uses a looser live profile; the still is
  /// checked with the full profile before it is accepted.
  static LiveIdAssessment confirmLive({
    required LiveIdAssessment luma,
    required DocumentEvidence evidence,
    required SellerIdType expectedType,
    required IdCaptureSide expectedSide,
    bool sessionTypeConfirmed = false,
  }) {
    if (!luma.isAligned) return luma;
    final geometry = luma.geometry;
    if (geometry == null || !evidence.available) {
      return LiveIdAssessment(
        status: LiveIdStatus.notId,
        occupancy: luma.occupancy,
        geometry: geometry,
        message: notDetectedMessage(expectedType),
      );
    }
    final rejected = rejection(
      evidence: evidence,
      geometry: geometry,
      expectedType: expectedType,
      expectedSide: expectedSide,
      sessionTypeConfirmed: sessionTypeConfirmed,
      live: true,
    );
    if (rejected != null) {
      return LiveIdAssessment(
        status: _liveStatus(rejected.issue),
        occupancy: luma.occupancy,
        geometry: geometry,
        message: rejected.message,
      );
    }
    return LiveIdAssessment(
      status: LiveIdStatus.aligned,
      occupancy: luma.occupancy,
      geometry: geometry,
      message: 'Hold your ${expectedType.label} steady.',
    );
  }

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
  /// in this session. PhilSys / UMID backs often omit the title line, but a
  /// different ID is still rejected.
  ///
  /// [live] relaxes only the Digital National ID profile. See [confirmLive].
  static IdQualityResult? rejection({
    required DocumentEvidence evidence,
    required IdDocumentGeometry geometry,
    required SellerIdType expectedType,
    required IdCaptureSide expectedSide,
    bool sessionTypeConfirmed = false,
    bool live = false,
  }) {
    if (!evidence.available) {
      _trace(
        'expected_type=${expectedType.storageValue} '
        'expected_side=${expectedSide.name} document_detected=false',
      );
      return IdQualityResult.fail(
        IdQualityIssue.uncertain,
        message: notDetectedMessage(expectedType),
      );
    }

    final text = normalize(evidence.recognizedText);
    if (evidence.looksLikePaymentCard || isUnsupportedDocument(text)) {
      _trace(
        'expected_type=${expectedType.storageValue} '
        'expected_side=${expectedSide.name} type_match=unsupported',
      );
      return IdQualityResult.fail(
        IdQualityIssue.notSupportedId,
        message: wrongTypeMessage(expectedType),
      );
    }
    if (_blocksDisplayedImage(evidence, expectedType)) {
      _trace(
        'expected_type=${expectedType.storageValue} '
        'expected_side=${expectedSide.name} '
        'screen=${expectedType.presentedOnScreen ? 'unrelated' : 'physical'}',
      );
      return IdQualityResult.fail(
        IdQualityIssue.notId,
        message: expectedType.presentedOnScreen
            ? 'Show your Digital National ID.'
            : 'Use your physical ${expectedType.label}. Photos of a screen are not accepted.',
      );
    }
    if (evidence.faceCoverage > IdImageMetrics.maxSelfieFaceCoverage) {
      _trace(
        'expected_type=${expectedType.storageValue} '
        'expected_side=${expectedSide.name} non_document=true',
      );
      return IdQualityResult.fail(
        IdQualityIssue.notId,
        message: notDetectedMessage(expectedType),
      );
    }

    if (expectedType == SellerIdType.digitalNationalId) {
      return _digitalRejection(
        text: text,
        evidence: evidence,
        geometry: geometry,
        expectedSide: expectedSide,
        sessionTypeConfirmed: sessionTypeConfirmed,
        live: live,
      );
    }

    final type = classifyType(text, expectedType);
    final side = classifySide(
      text: text,
      evidence: evidence,
      geometry: geometry,
      expectedType: expectedType,
    );

    _trace(
      'expected_type=${expectedType.storageValue} '
      'expected_side=${expectedSide.name} '
      'document_detected=true '
      'type_match=${type.name} '
      'side=${side.name} '
      'face=${evidence.faceCoverage.toStringAsFixed(2)} '
      'ocr_chars=${evidence.alphanumericChars}',
    );

    if (type == IdTypeDecision.unsupported) {
      return IdQualityResult.fail(
        IdQualityIssue.notSupportedId,
        message: wrongTypeMessage(expectedType),
      );
    }
    if (type == IdTypeDecision.mismatch) {
      return IdQualityResult.fail(
        IdQualityIssue.wrongIdType,
        message: wrongTypeMessage(expectedType),
      );
    }

    if (side == IdSideDecision.unknown) {
      return IdQualityResult.fail(
        IdQualityIssue.uncertain,
        message: notDetectedMessage(expectedType),
      );
    }
    final expected = expectedSide == IdCaptureSide.front
        ? IdSideDecision.front
        : IdSideDecision.back;
    if (side != expected) {
      return IdQualityResult.fail(
        IdQualityIssue.wrongSide,
        message: wrongSideMessage(expectedSide, expectedType),
      );
    }

    final typeOk =
        type == IdTypeDecision.match ||
        (type == IdTypeDecision.unknown &&
            _layoutSupportsSelected(
              expectedType: expectedType,
              expectedSide: expectedSide,
              text: text,
              evidence: evidence,
              geometry: geometry,
              sessionTypeConfirmed: sessionTypeConfirmed,
            ));
    if (!typeOk) {
      return IdQualityResult.fail(
        IdQualityIssue.uncertain,
        message: notDetectedMessage(expectedType),
      );
    }
    _trace(
      'accept expected_type=${expectedType.storageValue} '
      'expected_side=${expectedSide.name}',
    );
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
    // A Digital National ID also contains the words "national id".
    // Those words must not make it the physical card.
    if ((scores[SellerIdType.digitalNationalId] ?? 0) >= typeMatchThreshold) {
      scores[SellerIdType.nationalId] = 0;
    }
    final expectedScore = scores[expected] ?? 0;
    var bestType = expected;
    var bestScore = -1;
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

    if (bestScore < typeMatchThreshold) return IdTypeDecision.unknown;
    if (tied && bestScore == expectedScore) return IdTypeDecision.unknown;
    if (bestType != expected) return IdTypeDecision.mismatch;
    if (expectedScore < typeMatchThreshold) return IdTypeDecision.unknown;
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
    final portrait = _hasIdPortrait(evidence, expectedType);
    final machineCode = _hasMachineCode(geometry, normalized);
    final mrz = _hasMrz(evidence.recognizedText);
    final frontFields = _termHits(normalized, _frontIdentityTerms);
    final reverseFields = _termHits(normalized, _backTermsFor(expectedType));

    if (expectedType == SellerIdType.passport && mrz && reverseFields == 0) {
      return IdSideDecision.front;
    }

    // Portrait is the front discriminator. Digital PhilIDs print a QR on the
    // photo side, so QR/barcode labels must not override a real ID photo.
    if (portrait && reverseFields == 0) {
      return IdSideDecision.front;
    }
    if (portrait && frontFields > 0 && reverseFields < 2) {
      return IdSideDecision.front;
    }

    if (frontFields >= 2 && reverseFields == 0) {
      return IdSideDecision.front;
    }

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

  /// Title OCR often misses stylized headers. A selected type may still be
  /// confirmed from several field labels plus a portrait or back structure.
  /// A single token such as "UMID" or "SSS" is not enough.
  static bool _layoutSupportsSelected({
    required SellerIdType expectedType,
    required IdCaptureSide expectedSide,
    required String text,
    required DocumentEvidence evidence,
    required IdDocumentGeometry geometry,
    required bool sessionTypeConfirmed,
  }) {
    if (_foreignStrong(text, expectedType)) return false;
    if (expectedSide == IdCaptureSide.front) {
      return _frontLayout(
        expectedType: expectedType,
        text: text,
        evidence: evidence,
      );
    }
    return _backLayout(
      expectedType: expectedType,
      text: text,
      evidence: evidence,
      geometry: geometry,
      sessionTypeConfirmed: sessionTypeConfirmed,
    );
  }

  static bool _frontLayout({
    required SellerIdType expectedType,
    required String text,
    required DocumentEvidence evidence,
  }) {
    switch (expectedType) {
      case SellerIdType.nationalId:
        final identity =
            _hasTerm(text, 'given name') ||
            _hasTerm(text, 'last name') ||
            _hasTerm(text, 'surname');
        if (!identity || !_hasTerm(text, 'date of birth')) return false;
        if (!_hasIdPortrait(evidence)) return false;
        return evidence.blockCount >= 3;
      case SellerIdType.digitalNationalId:
        return false;
      case SellerIdType.driversLicense:
        return _hasIdPortrait(evidence) &&
            _hasTerm(text, 'date of birth') &&
            (_hasTerm(text, 'last name') || _hasTerm(text, 'given name')) &&
            (_hasTerm(text, 'license') ||
                _hasTerm(text, 'lto') ||
                _hasTerm(text, 'non professional') ||
                _hasTerm(text, 'nonprofessional'));
      case SellerIdType.passport:
        final mrz = _hasMrz(evidence.recognizedText);
        if (mrz && _hasIdPortrait(evidence)) return true;
        if (mrz && evidence.alphanumericChars >= 28) return true;
        return _hasIdPortrait(evidence) &&
            (_hasTerm(text, 'passport') || _hasTerm(text, 'pasaporte')) &&
            (_hasTerm(text, 'surname') ||
                _hasTerm(text, 'nationality') ||
                _hasTerm(text, 'date of birth'));
      case SellerIdType.sssId:
        if (!_hasIdPortrait(evidence)) return false;
        final titled =
            _hasTerm(text, 'social security system') ||
            _hasTerm(text, 'sss id');
        final number = _hasTerm(text, 'ss number') || _hasTerm(text, 'sss no');
        final person =
            _hasTerm(text, 'date of birth') || _hasTerm(text, 'signature');
        if (titled && person) return true;
        return number && person && _hasTerm(text, 'sss');
      case SellerIdType.umidId:
        if (!_hasIdPortrait(evidence)) return false;
        final titled =
            _hasTerm(text, 'unified multi purpose') ||
            _hasTerm(text, 'unified multipurpose');
        if (titled) return true;
        return _hasTerm(text, 'umid') &&
            (_hasTerm(text, 'crn') || _hasTerm(text, 'gsis'));
    }
  }

  static bool _backLayout({
    required SellerIdType expectedType,
    required String text,
    required DocumentEvidence evidence,
    required IdDocumentGeometry geometry,
    required bool sessionTypeConfirmed,
  }) {
    if (_hasIdPortrait(evidence)) return false;
    final hits = _termHits(text, _backTermsFor(expectedType));
    final hinted = _typeScore(text, expectedType) >= 1;
    final machine = _hasMachineCode(geometry, text);
    if (hinted && hits >= 1) return true;
    if (!sessionTypeConfirmed) return false;
    if (expectedType == SellerIdType.passport) {
      if (_hasMrz(evidence.recognizedText)) return false;
      return hits >= 1;
    }
    if (hits >= 2) return true;
    return hits >= 1 && machine;
  }

  static bool _blocksDisplayedImage(
    DocumentEvidence evidence,
    SellerIdType expectedType,
  ) {
    if (evidence.looksLikeUnrelatedScreen) return true;
    if (expectedType.presentedOnScreen) return false;
    return evidence.looksLikeDisplayedImage;
  }

  static IdQualityResult? _digitalRejection({
    required String text,
    required DocumentEvidence evidence,
    required IdDocumentGeometry geometry,
    required IdCaptureSide expectedSide,
    required bool sessionTypeConfirmed,
    required bool live,
  }) {
    const expectedType = SellerIdType.digitalNationalId;
    final type = classifyType(text, expectedType);
    final side = classifySide(
      text: text,
      evidence: evidence,
      geometry: geometry,
      expectedType: expectedType,
    );
    final physicalMarker = _termHits(text, _physicalPhilIdTerms) > 0;

    _trace(
      'expected_type=${expectedType.storageValue} '
      'expected_side=${expectedSide.name} '
      'document_detected=true live=$live '
      'type_match=${type.name} '
      'side=${side.name} '
      'face=${evidence.faceCoverage.toStringAsFixed(2)} '
      'ocr_chars=${evidence.alphanumericChars}',
    );

    if (type == IdTypeDecision.unsupported) {
      return IdQualityResult.fail(
        IdQualityIssue.notSupportedId,
        message: wrongTypeMessage(expectedType),
      );
    }
    if (type == IdTypeDecision.mismatch) {
      // Both PhilSys credentials share the header. A preview frame that only
      // read the header is left to the still, which needs a digital marker.
      final philSysHeaderOnly =
          !physicalMarker &&
          classifyType(text, SellerIdType.nationalId) == IdTypeDecision.match;
      if (!live || !philSysHeaderOnly) {
        return IdQualityResult.fail(
          IdQualityIssue.wrongIdType,
          message: wrongTypeMessage(expectedType),
        );
      }
    }

    final expected = expectedSide == IdCaptureSide.front
        ? IdSideDecision.front
        : IdSideDecision.back;
    if (side != IdSideDecision.unknown && side != expected) {
      return IdQualityResult.fail(
        IdQualityIssue.wrongSide,
        message: wrongSideMessage(expectedSide, expectedType),
      );
    }

    final matches = expectedSide == IdCaptureSide.front
        ? _digitalFrontMatches(
            text: text,
            evidence: evidence,
            physicalMarker: physicalMarker,
            live: live,
          )
        : _digitalBackMatches(
            text: text,
            evidence: evidence,
            geometry: geometry,
            physicalMarker: physicalMarker,
            sessionTypeConfirmed: sessionTypeConfirmed,
            live: live,
          );
    if (!matches) {
      return IdQualityResult.fail(
        IdQualityIssue.uncertain,
        message: notDetectedMessage(expectedType),
      );
    }
    _trace(
      'accept expected_type=${expectedType.storageValue} '
      'expected_side=${expectedSide.name} live=$live',
    );
    return null;
  }

  /// eGov app front: PhilSys header, "Philippine National ID", a small
  /// photo, name / birth date / address labels, a QR, and a
  /// "Digital ID Number". The physical card prints "Philippine
  /// Identification Card" instead. This does not check the everify signature.
  static bool _digitalFrontMatches({
    required String text,
    required DocumentEvidence evidence,
    required bool physicalMarker,
    required bool live,
  }) {
    if (physicalMarker) return false;
    final marker = _termHits(text, _digitalMarkerTerms) > 0;
    final header = _termHits(text, _philSysHeaderTerms) > 0;
    final portrait = _hasIdPortrait(evidence, SellerIdType.digitalNationalId);
    final fields = _termHits(text, _digitalFrontFieldTerms);
    final date = _hasWrittenDate(text);

    if (live) {
      final signals = [
        marker,
        header,
        portrait,
        fields >= 2 || date,
      ].where((signal) => signal).length;
      return signals >= 2;
    }
    return marker &&
        (portrait || fields >= 3) &&
        (fields >= 1 || date) &&
        evidence.blockCount >= 3;
  }

  /// eGov app back: sex, blood type, marital status, place of birth, and a
  /// large QR. No photo and no issue date (the physical card has one).
  static bool _digitalBackMatches({
    required String text,
    required DocumentEvidence evidence,
    required IdDocumentGeometry geometry,
    required bool physicalMarker,
    required bool sessionTypeConfirmed,
    required bool live,
  }) {
    if (physicalMarker) return false;
    if (_hasIdPortrait(evidence, SellerIdType.digitalNationalId)) {
      return false;
    }
    final code = _hasMachineCode(geometry, text);
    var demographics = 0;
    for (final field in _digitalBackFieldGroups) {
      if (_termHits(text, field) > 0) demographics++;
    }
    if (live) {
      return demographics >= 1 || (sessionTypeConfirmed && code);
    }
    if (demographics >= 3) return true;
    if (demographics >= 2 && (sessionTypeConfirmed || code)) return true;
    return demographics >= 1 && sessionTypeConfirmed && code;
  }

  static bool _hasWrittenDate(String text) => RegExp(
    r'\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]* '
    r'\d{1,2} (19|20)\d{2}\b',
  ).hasMatch(text);

  static bool _foreignStrong(String text, SellerIdType expected) {
    for (final type in SellerIdType.values) {
      if (type == expected) continue;
      if (_strongScore(text, type) >= typeMatchThreshold) return true;
    }
    return false;
  }

  static bool _hasIdPortrait(DocumentEvidence evidence, [SellerIdType? type]) {
    final face = evidence.faceCoverage;
    final minFace = type?.presentedOnScreen == true
        ? IdImageMetrics.minDisplayedFaceCoverage
        : IdImageMetrics.minFrontFaceCoverage;
    if (face < minFace || face > IdImageMetrics.maxFrontFaceCoverage) {
      return false;
    }
    final x = evidence.faceCenterX;
    if (x != null && x > 0.62) {
      // PH ID portraits sit on the left or center of the document crop.
      return false;
    }
    return true;
  }

  static bool _hasMachineCode(IdDocumentGeometry geometry, String text) {
    if (_hasTerm(text, 'qr code') || _hasTerm(text, 'barcode')) return true;
    return geometry.moduleScore >= IdImageMetrics.denseQrModuleScore;
  }

  /// ICAO TD3 machine-readable zone. Chevrons are checked before [normalize].
  static bool _hasMrz(String raw) {
    if (raw.isEmpty) return false;
    final compact = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9<]'), '');
    if (compact.contains('P<PHL') || compact.contains('P<PH')) return true;
    final chevrons = '<'.allMatches(raw).length;
    return chevrons >= 8 && compact.length >= 40;
  }

  static int _typeScore(String text, SellerIdType type) =>
      _strongScore(text, type) + _weakScore(text, type);

  static int _strongScore(String text, SellerIdType type) {
    var score = 0;
    for (final term in _strongTerms[type]!) {
      if (_hasTerm(text, term)) score += 2;
    }
    return score;
  }

  static int _weakScore(String text, SellerIdType type) {
    var score = 0;
    for (final term in _weakTerms[type]!) {
      if (_hasTerm(text, term)) score += 1;
    }
    return score;
  }

  static List<String> _backTermsFor(SellerIdType type) => switch (type) {
    SellerIdType.nationalId => _nationalIdBackTerms,
    SellerIdType.digitalNationalId => _digitalNationalBackTerms,
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

  static LiveIdStatus _liveStatus(IdQualityIssue? issue) => switch (issue) {
    IdQualityIssue.wrongSide => LiveIdStatus.wrongSide,
    IdQualityIssue.blurry || IdQualityIssue.slightlySoft => LiveIdStatus.blurry,
    IdQualityIssue.tooDark ||
    IdQualityIssue.lowContrast => LiveIdStatus.tooDark,
    IdQualityIssue.tooFar => LiveIdStatus.tooFar,
    IdQualityIssue.poorFraming => LiveIdStatus.poorlyFramed,
    _ => LiveIdStatus.notId,
  };

  static void _trace(String message) {
    if (kDebugMode) {
      debugPrint('ID_CAPTURE $message');
    }
  }

  static const Map<SellerIdType, List<String>> _strongTerms = {
    SellerIdType.nationalId: [
      'philippine identification',
      'pambansang pagkakakilanlan',
      'national identification',
      'philippine identification system',
    ],
    SellerIdType.digitalNationalId: [
      'digital national id',
      'digital id number',
      'philippine national id',
    ],
    SellerIdType.driversLicense: [
      'drivers license',
      'driver license',
      'driver s license',
      'land transportation office',
      'non professional',
      'nonprofessional',
    ],
    SellerIdType.passport: ['department of foreign affairs'],
    SellerIdType.sssId: ['social security system', 'sss id'],
    SellerIdType.umidId: [
      'unified multi purpose',
      'unified multipurpose',
      'gsis umid',
    ],
  };

  static const Map<SellerIdType, List<String>> _weakTerms = {
    SellerIdType.nationalId: [
      'philsys',
      'phil sys',
      'pagkakakilanlan',
      'pambansang',
      'national id',
      'philsys card',
      'philsys number',
    ],
    SellerIdType.digitalNationalId: ['national id card number'],
    SellerIdType.driversLicense: ['land transportation', 'lto'],
    SellerIdType.passport: ['passport', 'pasaporte', 'dfa'],
    SellerIdType.sssId: ['ss number', 'sss no', 'sss'],
    SellerIdType.umidId: ['umid', 'crn'],
  };

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

  static const List<String> _nationalIdBackTerms = [
    'blood type',
    'marital status',
    'place of birth',
    'date issued',
    'date of issue',
    'this is to certify',
  ];

  /// "Digital ID Number" is printed on the front of the eGov card, not here.
  static const List<String> _digitalNationalBackTerms = [
    'blood type',
    'uri ng dugo',
    'marital status',
    'kalagayang sibil',
    'place of birth',
    'lugar ng kapanganakan',
    'kasarian',
  ];

  static const List<String> _digitalMarkerTerms = [
    'digital id',
    'digital national id',
    'philippine national id',
  ];

  static const List<String> _philSysHeaderTerms = [
    'pambansang pagkakakilanlan',
    'republika ng pilipinas',
    'republic of the philippines',
  ];

  static const List<String> _digitalFrontFieldTerms = [
    'last name',
    'given name',
    'middle name',
    'date of birth',
    'address',
    'apelyido',
    'mga pangalan',
    'petsa ng kapanganakan',
    'tirahan',
  ];

  /// One entry per printed field, so the English and Filipino label for the
  /// same field count once. Values are included because labels are tiny.
  static const List<List<String>> _digitalBackFieldGroups = [
    ['sex', 'kasarian', 'male', 'female'],
    ['blood type', 'uri ng dugo', 'unknown'],
    [
      'marital status',
      'kalagayang sibil',
      'single',
      'married',
      'widowed',
      'separated',
      'annulled',
    ],
    ['place of birth', 'lugar ng kapanganakan'],
  ];

  /// Printed only on the physical PhilID card.
  static const List<String> _physicalPhilIdTerms = [
    'identification card',
    'date issued',
    'date of issue',
    'this is to certify',
  ];

  static const List<String> _driversBackTerms = ['restrictions', 'conditions'];

  static const List<String> _passportBackTerms = [
    'observations',
    'amendments',
    'endorsements',
  ];

  static const List<String> _sssBackTerms = [
    'signature of',
    'in case of emergency',
  ];

  static const List<String> _umidBackTerms = ['in case of emergency'];

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
