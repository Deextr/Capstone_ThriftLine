import 'ph_phone.dart';

/// Shown when a known Smart/TNT prefix is detected (pre-check only; not proof of network).
const String kSmartTntPrefixUnavailableMessage =
    'Smart & TNT verification is temporarily unavailable. Please use another supported mobile number.';

/// First four digits (`09XX`) commonly assigned to Smart / TNT (Philippines).
///
/// Pre-check only — mobile number portability means the live network may differ.
/// Update this set in one place when product/ops refreshes the list.
const Set<String> kSmartTntMobilePrefixesFourDigit = {
  '0908',
  '0910',
  '0911',
  '0912',
  '0913',
  '0914',
  '0918',
  '0919',
  '0920',
  '0921',
  '0928',
  '0929',
  '0930',
  '0938',
  '0939',
  '0940',
  '0946',
  '0947',
  '0948',
  '0949',
  '0950',
  '0951',
  '0961',
  '0963',
  '0968',
  '0969',
  '0970',
  '0981',
  '0989',
  '0992',
  '0998',
  '0999',
};

/// `local11` must be exactly `09XXXXXXXXX`.
bool isKnownSmartOrTntPrefix(String local11) {
  if (local11.length < 4) return false;
  return kSmartTntMobilePrefixesFourDigit.contains(local11.substring(0, 4));
}

/// Prefix lists are not used to block OTP.
///
/// TM (Touch Mobile) and Smart/TNT publish overlapping `09XX` blocks, and
/// mobile number portability means the live network can differ from the
/// original prefix. Carrier failures come from the UniSMS response instead.
String? smartTntPrefixOtpBlockMessage(String local11) {
  if (!isPhMobile09Format(local11)) return null;
  return null;
}
