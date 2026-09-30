/// The signed-in person's own account details (shared across clubs).
class MyProfileDetails {
  const MyProfileDetails({
    required this.profileId,
    required this.displayName,
    required this.revision,
    this.contactEmail,
    this.phone,
    this.hasAvatar = false,
    this.loginEmail,
    this.emailChange,
    this.streetAddress,
    this.postalCode,
    this.city,
  });
  final String profileId, displayName;
  final String? contactEmail, phone, loginEmail;
  final String? streetAddress, postalCode, city;
  final bool hasAvatar;
  final int revision;

  /// Latest request to change the login email, if any.
  final LoginEmailChange? emailChange;

  factory MyProfileDetails.fromJson(Map<String, dynamic> json) =>
      MyProfileDetails(
        profileId: json['profile_id'] as String,
        displayName: json['display_name'] as String? ?? '',
        contactEmail: json['contact_email'] as String?,
        phone: json['phone'] as String?,
        hasAvatar: json['has_avatar'] as bool? ?? false,
        loginEmail: json['login_email'] as String?,
        streetAddress: json['street_address'] as String?,
        postalCode: json['postal_code'] as String?,
        city: json['city'] as String?,
        revision: (json['revision'] as num? ?? 1).toInt(),
        emailChange: json['email_change'] is Map<String, dynamic>
            ? LoginEmailChange.fromJson(
                json['email_change'] as Map<String, dynamic>,
              )
            : null,
      );
}

/// A request to change the login email; support decides on it.
class LoginEmailChange {
  const LoginEmailChange({
    required this.id,
    required this.requestedEmail,
    required this.state,
    this.displayName,
    this.currentEmail,
    this.reason,
    this.decisionNote,
    this.createdAt,
  });
  final String id, requestedEmail, state;
  final String? displayName, currentEmail, reason, decisionNote;
  final DateTime? createdAt;

  bool get isOpen => state == 'pending' || state == 'approved';

  factory LoginEmailChange.fromJson(Map<String, dynamic> json) =>
      LoginEmailChange(
        id: json['id'] as String,
        requestedEmail: json['requested_email'] as String,
        state: json['state'] as String,
        displayName: json['display_name'] as String?,
        currentEmail: json['current_email'] as String?,
        reason: json['reason'] as String?,
        decisionNote: json['decision_note'] as String?,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      );
}

/// Contact details and picture of a team member, as far as the viewer may
/// see them (the person and the team's leaders see contact details).
class PersonContact {
  const PersonContact({
    this.avatarProfileId,
    this.canSeeContact = false,
    this.canEditClubContact = false,
    this.contactEmail,
    this.phone,
    this.contactSource,
    this.hasAccount = false,
    this.streetAddress,
    this.postalCode,
    this.city,
  });
  final String? avatarProfileId, contactEmail, phone, contactSource;
  final String? streetAddress, postalCode, city;

  bool get hasAddress => [
    streetAddress,
    postalCode,
    city,
  ].any((part) => part != null && part.trim().isNotEmpty);
  final bool canSeeContact, canEditClubContact, hasAccount;

  factory PersonContact.fromJson(Map<String, dynamic> json) => PersonContact(
    avatarProfileId: json['avatar_profile_id'] as String?,
    canSeeContact: json['can_see_contact'] as bool? ?? false,
    canEditClubContact: json['can_edit_club_contact'] as bool? ?? false,
    contactEmail: json['contact_email'] as String?,
    phone: json['phone'] as String?,
    contactSource: json['contact_source'] as String?,
    hasAccount: json['has_account'] as bool? ?? false,
    streetAddress: json['street_address'] as String?,
    postalCode: json['postal_code'] as String?,
    city: json['city'] as String?,
  );
}

/// The virtual member card: front for club members, back (contact) only for
/// the person and the team's leaders.
class MemberCard {
  const MemberCard({
    required this.personId,
    required this.name,
    required this.clubId,
    required this.clubName,
    required this.teamName,
    required this.memberNumber,
    this.hasBadge = false,
    this.roles = const [],
    this.titles = const [],
    this.customTitles = const [],
    this.guardianOf = const [],
    this.birthYear,
    this.memberSince,
    this.contact = const PersonContact(),
  });
  final String personId, name, clubId, clubName, teamName, memberNumber;
  final bool hasBadge;
  final List<String> roles, titles, customTitles, guardianOf;
  final int? birthYear;
  final DateTime? memberSince;
  final PersonContact contact;

  static List<String> _strings(Object? raw) =>
      (raw as List? ?? const []).whereType<String>().toList(growable: false);

  factory MemberCard.fromJson(Map<String, dynamic> json) => MemberCard(
    personId: json['person_id'] as String,
    name: json['name'] as String? ?? '',
    clubId: json['club_id'] as String,
    clubName: json['club_name'] as String? ?? '',
    teamName: json['team_name'] as String? ?? '',
    memberNumber: json['member_number'] as String? ?? '',
    hasBadge: json['has_badge'] as bool? ?? false,
    roles: _strings(json['roles']),
    titles: _strings(json['titles']),
    customTitles: _strings(json['custom_titles']),
    guardianOf: _strings(json['guardian_of']),
    birthYear: (json['birth_year'] as num?)?.toInt(),
    memberSince: DateTime.tryParse(json['member_since'] as String? ?? ''),
    contact: json['contact'] is Map<String, dynamic>
        ? PersonContact.fromJson(json['contact'] as Map<String, dynamic>)
        : const PersonContact(),
  );
}

/// Figures on the member profile. [app] is only filled in on your own
/// profile.
class PersonStatistics {
  const PersonStatistics({
    this.isSelf = false,
    this.trainingsTotal = 0,
    this.trainingsAttended = 0,
    this.matchesTotal = 0,
    this.matchesPlayed = 0,
    this.goals = 0,
    this.assists = 0,
    this.cards = 0,
    this.callupsReceived = 0,
    this.callupsAccepted = 0,
    this.callupsDeclined = 0,
    this.callupsAnswered = 0,
    this.averageResponseMinutes,
    this.app,
  });
  final bool isSelf;
  final int trainingsTotal, trainingsAttended, matchesTotal, matchesPlayed;
  final int goals, assists, cards;
  final int callupsReceived, callupsAccepted, callupsDeclined, callupsAnswered;
  final int? averageResponseMinutes;
  final AppUsage? app;

  static int _int(Map<String, dynamic>? json, String key) =>
      (json?[key] as num? ?? 0).toInt();

  factory PersonStatistics.fromJson(Map<String, dynamic> json) {
    final sport = json['sport'] as Map<String, dynamic>?;
    final callups = json['callups'] as Map<String, dynamic>?;
    final app = json['app'] as Map<String, dynamic>?;
    return PersonStatistics(
      isSelf: json['is_self'] as bool? ?? false,
      trainingsTotal: _int(sport, 'trainings_total'),
      trainingsAttended: _int(sport, 'trainings_attended'),
      matchesTotal: _int(sport, 'matches_total'),
      matchesPlayed: _int(sport, 'matches_played'),
      goals: _int(sport, 'goals'),
      assists: _int(sport, 'assists'),
      cards: _int(sport, 'cards'),
      callupsReceived: _int(callups, 'received'),
      callupsAccepted: _int(callups, 'accepted'),
      callupsDeclined: _int(callups, 'declined'),
      callupsAnswered: _int(callups, 'answered'),
      averageResponseMinutes: (callups?['avg_response_minutes'] as num?)
          ?.round(),
      app: app == null
          ? null
          : AppUsage(
              messagesSent: _int(app, 'messages_sent'),
              activeDays30: _int(app, 'active_days_30'),
              currentStreak: _int(app, 'current_streak'),
              longestStreak: _int(app, 'longest_streak'),
            ),
    );
  }
}

class AppUsage {
  const AppUsage({
    required this.messagesSent,
    required this.activeDays30,
    required this.currentStreak,
    required this.longestStreak,
  });
  final int messagesSent, activeDays30, currentStreak, longestStreak;
}

/// Raised with the server's reason code, e.g. invalid_email, request_open.
class ProfileException implements Exception {
  const ProfileException(this.code);
  final String code;
  @override
  String toString() => 'ProfileException($code)';
}
