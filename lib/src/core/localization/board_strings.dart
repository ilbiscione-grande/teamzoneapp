import 'package:flutter/widgets.dart';

class BoardStrings {
  const BoardStrings._(this.isSwedish);
  final bool isSwedish;

  static BoardStrings of(BuildContext context) => BoardStrings._(
    Localizations.localeOf(context).languageCode.toLowerCase() == 'sv',
  );

  String get title => isSwedish ? 'Styrelse' : 'Board';
  String get noAccess => isSwedish
      ? 'Du saknar behörighet att visa styrelsemandat.'
      : 'You do not have permission to view board mandates.';
  String get inactiveTitle =>
      isSwedish ? 'Styrelse är inte aktiv' : 'Board is not active';
  String get inactiveMessage => isSwedish
      ? 'Modulen måste vara aktiv och du måste ha rätt behörighet.'
      : 'The module must be active and you need the required permission.';
  String get proposeMandate =>
      isSwedish ? 'Föreslå styrelsemandat' : 'Propose board mandate';
  String get person => isSwedish ? 'Person' : 'Person';
  String get officeLabel => isSwedish ? 'Uppdrag' : 'Office';
  String get next => isSwedish ? 'Nästa' : 'Next';
  String get newMandate => isSwedish ? 'Nytt mandat' : 'New mandate';
  String get mandatesHeading => isSwedish
      ? 'Aktiva och historiska mandat'
      : 'Active and historical mandates';
  String get noMandates =>
      isSwedish ? 'Inga styrelsemandat ännu.' : 'No board mandates yet.';
  String get changesHeading =>
      isSwedish ? 'Mandatändringar' : 'Mandate changes';
  String get noChanges => isSwedish
      ? 'Inga väntande eller historiska ändringar.'
      : 'No pending or historical changes.';
  String get proposeRevocation =>
      isSwedish ? 'Föreslå återkallelse' : 'Propose revocation';
  String get assign => isSwedish ? 'Tilldela' : 'Grant';
  String get revoke => isSwedish ? 'Återkalla' : 'Revoke';
  String get alreadyApproved =>
      isSwedish ? 'Du har redan godkänt' : 'You have already approved';
  String get approve => isSwedish ? 'Godkänn' : 'Approve';
  String get approveChange =>
      isSwedish ? 'Godkänn mandatändring' : 'Approve mandate change';
  String get applyAfterApprovals =>
      isSwedish ? 'Verkställ efter 2 godkännanden' : 'Apply after 2 approvals';
  String approvals(int count) =>
      isSwedish ? '$count av 2 godkännanden' : '$count of 2 approvals';

  String office(String value) => switch (value) {
    'chair' => isSwedish ? 'Ordförande' : 'Chair',
    'treasurer' => isSwedish ? 'Kassör' : 'Treasurer',
    'secretary' => isSwedish ? 'Sekreterare' : 'Secretary',
    'member' => isSwedish ? 'Ledamot' : 'Board member',
    'auditor' => isSwedish ? 'Revisor' : 'Auditor',
    _ => value,
  };

  String state(String value) => switch (value) {
    'scheduled' => isSwedish ? 'Planerat' : 'Scheduled',
    'active' => isSwedish ? 'Aktivt' : 'Active',
    'ended' => isSwedish ? 'Avslutat' : 'Ended',
    'revoked' => isSwedish ? 'Återkallat' : 'Revoked',
    'pending' => isSwedish ? 'Väntar' : 'Pending',
    'applied' => isSwedish ? 'Verkställt' : 'Applied',
    'rejected' => isSwedish ? 'Avslaget' : 'Rejected',
    _ => value,
  };

  String error(Object error) {
    final value = error.toString();
    if (value.contains('mandate_approval_denied')) {
      return isSwedish
          ? 'Den som skapade ändringen får inte godkänna den.'
          : 'The person who proposed the change cannot approve it.';
    }
    if (value.contains('mandate_approval_already_recorded')) {
      return alreadyApproved;
    }
    if (value.contains('mandate_approval_required')) {
      return isSwedish
          ? '2 godkännanden krävs innan ändringen kan verkställas.'
          : '2 approvals are required before the change can be applied.';
    }
    if (value.contains('mandate_overlap')) {
      return isSwedish
          ? 'Mandatet överlappar ett befintligt aktivt mandat.'
          : 'The mandate overlaps an existing active mandate.';
    }
    return isSwedish
        ? 'Åtgärden kunde inte genomföras. Försök igen.'
        : 'The action could not be completed. Please try again.';
  }
}
