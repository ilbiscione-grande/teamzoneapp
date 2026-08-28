import 'package:flutter/widgets.dart';

class EconomyStrings {
  const EconomyStrings._(this.isSwedish);
  final bool isSwedish;

  static EconomyStrings of(BuildContext context) => EconomyStrings._(
    Localizations.localeOf(context).languageCode.toLowerCase() == 'sv',
  );

  String get title => 'Economy';
  String get noAccess => isSwedish
      ? 'Du saknar behörighet att visa klubbens ekonomi.'
      : 'You do not have permission to view the club economy.';
  String get inactiveTitle =>
      isSwedish ? 'Economy är inte aktiv' : 'Economy is not active';
  String get inactiveMessage => isSwedish
      ? 'Modulen måste aktiveras för klubben innan ekonomidata kan visas.'
      : 'The module must be activated for the club before economy data can be shown.';
  String get newAccount => isSwedish ? 'Ny kassa' : 'New account';
  String get accountName => isSwedish ? 'Namn' : 'Name';
  String get newEntry => isSwedish ? 'Ny ekonomipost' : 'New economy entry';
  String get newEntryShort => isSwedish ? 'Ny post' : 'New entry';
  String get account => isSwedish ? 'Kassa' : 'Account';
  String get type => isSwedish ? 'Typ' : 'Type';
  String get inflow => isSwedish ? 'Inbetalning' : 'Inflow';
  String get outflow => isSwedish ? 'Utbetalning' : 'Outflow';
  String get amountSek =>
      isSwedish ? 'Belopp i kronor' : 'Amount in Swedish kronor';
  String get noAccounts => isSwedish ? 'Inga kassor' : 'No accounts';
  String get noAccountsMessage => isSwedish
      ? 'Skapa en klubb- eller lagkassa för att börja intern uppföljning.'
      : 'Create a club or team account to begin internal tracking.';
  String get clubAccount => isSwedish ? 'Klubbkassa' : 'Club account';
  String get teamAccount => isSwedish ? 'Lagkassa' : 'Team account';
  String get entries => isSwedish ? 'Poster' : 'Entries';
  String get noEntries =>
      isSwedish ? 'Inga ekonomiposter ännu.' : 'No economy entries yet.';
  String get alreadyApproved =>
      isSwedish ? 'Du har redan godkänt' : 'You have already approved';
  String get approve => isSwedish ? 'Godkänn' : 'Approve';
  String get approveEntry => isSwedish ? 'Godkänn post' : 'Approve entry';
  String get post => isSwedish ? 'Bokför' : 'Post';
  String get reverse => isSwedish ? 'Reversera' : 'Reverse';
  String get requestReversal =>
      isSwedish ? 'Begär reversering' : 'Request reversal';
  String get reversal => isSwedish ? 'Reversering' : 'Reversal';
  String approvals(int count, int required) => isSwedish
      ? '$count av $required godkännanden'
      : '$count of $required approvals';

  String state(String value) => switch (value) {
    'pending' => isSwedish ? 'Väntar' : 'Pending',
    'posted' => isSwedish ? 'Bokförd' : 'Posted',
    'rejected' => isSwedish ? 'Avslagen' : 'Rejected',
    'reversed' => isSwedish ? 'Reverserad' : 'Reversed',
    'requested' => isSwedish ? 'Begärd' : 'Requested',
    _ => value,
  };

  String category(String value) => switch (value) {
    'manual_entry' => isSwedish ? 'Manuell post' : 'Manual entry',
    'reversal' => isSwedish ? 'Reversering' : 'Reversal',
    _ => value,
  };

  String error(Object error) {
    final value = error.toString();
    if (value.contains('approval_denied')) {
      return isSwedish
          ? 'Du kan inte godkänna en post som du själv har skapat.'
          : 'You cannot approve an entry that you created.';
    }
    if (value.contains('approval_already_recorded')) {
      return isSwedish
          ? 'Du har redan attesterat den här posten.'
          : 'You have already approved this entry.';
    }
    if (value.contains('approval_required')) {
      return isSwedish
          ? 'Två oberoende godkännanden krävs innan posten kan bokföras.'
          : 'Two independent approvals are required before the entry can be posted.';
    }
    if (value.contains('approval_rejected')) {
      return isSwedish
          ? 'Posten har avslagits och kan inte bokföras.'
          : 'The entry was rejected and cannot be posted.';
    }
    return isSwedish
        ? 'Åtgärden kunde inte genomföras. Försök igen.'
        : 'The action could not be completed. Please try again.';
  }
}
