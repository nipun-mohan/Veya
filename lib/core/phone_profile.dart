class PhoneProfile {
  final String countryCode, nationalNumber;
  const PhoneProfile(this.countryCode, this.nationalNumber);
  String get number => '$countryCode$nationalNumber';

  static PhoneProfile? parse(String countryCode, String input) {
    final digits = input.replaceAll(RegExp(r'[\s()-]'), '');
    if (!RegExp(r'^\+[1-9]\d{0,2}$').hasMatch(countryCode) ||
        !RegExp(r'^\d{6,14}$').hasMatch(digits) ||
        !RegExp(r'^\+[1-9]\d{7,14}$').hasMatch('$countryCode$digits')) {
      return null;
    }
    if (countryCode == '+91' && !RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) {
      return null;
    }
    if (countryCode == '+1' && digits.length != 10) return null;
    return PhoneProfile(countryCode, digits);
  }
}
