class LegalStatus {
  const LegalStatus({
    required this.termsVersion,
    required this.termsUrl,
    required this.termsAccepted,
    required this.privacyVersion,
    required this.privacyUrl,
    required this.privacyAccepted,
    required this.marketingOptIn,
  });

  final String termsVersion, termsUrl, privacyVersion, privacyUrl;
  final bool termsAccepted, privacyAccepted, marketingOptIn;

  bool get requiresAcceptance => !termsAccepted || !privacyAccepted;

  factory LegalStatus.fromJson(Map<String, dynamic> json) => LegalStatus(
    termsVersion: json['terms_version'] as String,
    termsUrl: json['terms_url'] as String,
    termsAccepted: json['terms_accepted'] as bool,
    privacyVersion: json['privacy_version'] as String,
    privacyUrl: json['privacy_url'] as String,
    privacyAccepted: json['privacy_accepted'] as bool,
    marketingOptIn: json['marketing_opt_in'] as bool? ?? false,
  );
}
