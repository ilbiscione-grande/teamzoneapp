import 'package:flutter/foundation.dart';

/// An account can be deleted while someone is signed in to it (support
/// approves an erasure, or it is deleted on another device). The access
/// token stays valid for up to an hour, so the app asks the sign-in service
/// whether the account is still there, at start and when it comes back to
/// the foreground.
abstract interface class AccountPresenceCheck {
  /// Signs out on this device when the account or its session is gone; true
  /// if it did. A network failure is not taken as gone.
  Future<bool> signOutIfAccountGone();
}

/// The account was deleted; the app has signed out.
class AccountRemovedException implements Exception {
  const AccountRemovedException();
}

/// True after a sign-out because the account was deleted; the sign-in page
/// says so once and clears it.
final accountRemovedNotice = ValueNotifier<bool>(false);
