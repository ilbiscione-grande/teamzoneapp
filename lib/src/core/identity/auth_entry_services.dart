import 'package:flutter/foundation.dart';

enum AuthEntryEvent { passwordRecovery }

enum EmailChallengePurpose { signIn, signUp }

class PasswordSignUpResult {
  const PasswordSignUpResult({required this.verificationRequired});

  final bool verificationRequired;
}

abstract interface class AuthEntryServices {
  Stream<AuthEntryEvent> get entryEvents;

  Future<PasswordSignUpResult> signUpWithPassword({
    required String email,
    required String password,
  });

  Future<void> requestEmailChallenge({
    required String email,
    required EmailChallengePurpose purpose,
  });

  Future<void> verifyEmailChallenge({
    required String email,
    required String code,
  });

  Future<void> requestPasswordReset({required String email});

  Future<void> updatePassword({required String password});
}

class UnconfiguredAuthEntryServices implements AuthEntryServices {
  const UnconfiguredAuthEntryServices();

  Never get _unavailable =>
      throw StateError('Authentication is not configured.');

  @override
  Stream<AuthEntryEvent> get entryEvents => const Stream.empty();

  @override
  Future<void> requestEmailChallenge({
    required String email,
    required EmailChallengePurpose purpose,
  }) async => _unavailable;

  @override
  Future<void> requestPasswordReset({required String email}) async =>
      _unavailable;

  @override
  Future<PasswordSignUpResult> signUpWithPassword({
    required String email,
    required String password,
  }) async => _unavailable;

  @override
  Future<void> updatePassword({required String password}) async => _unavailable;

  @override
  Future<void> verifyEmailChallenge({
    required String email,
    required String code,
  }) async => _unavailable;
}

class EmailChallengeController extends ChangeNotifier {
  EmailChallengeController({
    DateTime Function()? now,
    this.cooldown = const Duration(seconds: 60),
    this.validFor = const Duration(minutes: 10),
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Duration cooldown;
  final Duration validFor;
  DateTime? _sentAt;

  bool get hasChallenge => _sentAt != null;
  bool get isExpired {
    final sent = _sentAt;
    return sent != null && !_now().isBefore(sent.add(validFor));
  }

  Duration get resendWait {
    final sent = _sentAt;
    if (sent == null) return Duration.zero;
    final remaining = sent.add(cooldown).difference(_now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool get canResend => hasChallenge && resendWait == Duration.zero;

  void markSent() {
    _sentAt = _now();
    notifyListeners();
  }

  void tick() => notifyListeners();

  void clear() {
    _sentAt = null;
    notifyListeners();
  }
}
