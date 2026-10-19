import 'package:supabase_flutter/supabase_flutter.dart';

/// REF-01: referees on matches. A match has 0–3 places (Huvuddomare,
/// Assisterande domare 1 and 2). A team's event managers propose referees
/// or write one in; referees and assigners search matches and offer to
/// referee. Both sides confirm when the other side can.

const refereeSlots = ['main', 'assistant_1', 'assistant_2'];

String refereeSlotLabel(String slot) => switch (slot) {
  'main' => 'Huvuddomare',
  'assistant_1' => 'Assisterande domare 1',
  'assistant_2' => 'Assisterande domare 2',
  _ => slot,
};

/// A database reason in Swedish, or a general message.
String refereeErrorText(Object error) {
  final text = error.toString();
  const known = {
    'slot_taken': 'Platsen är redan tillsatt eller har en förfrågan.',
    'slots_in_use': 'Ta bort domarna på de platser som försvinner först.',
    'not_a_match': 'Domare kan bara tillsättas på matcher som ska spelas.',
    'not_a_referee': 'Personen är inte domare längre.',
    'not_pending': 'Förfrågan är redan besvarad.',
    'too_young': 'Domaren behöver vara minst 3 år äldre än lagets spelare.',
    'no_assignment': 'Personen behöver ha en roll i klubben först.',
    'nothing_to_pay': 'Det finns inga godkända uppdrag att betala ut.',
    'in_payout': 'Uppdraget finns redan på en utbetalningslista.',
  };
  for (final entry in known.entries) {
    if (text.contains(entry.key)) return entry.value;
  }
  return 'Det gick inte att spara. Försök igen.';
}

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

List<Map<String, dynamic>> _maps(Object? value) => [
  if (value is List)
    for (final row in value.whereType<Map>()) row.cast<String, dynamic>(),
];

int _int(Object? value) => (value as num?)?.toInt() ?? 0;

/// "1 250 kr", with a non-breaking space between thousands.
String formatKronor(int amount) {
  final digits = amount.abs().toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write('\u00a0');
    grouped.write(digits[i]);
  }
  return '${amount < 0 ? '-' : ''}$grouped\u00a0kr';
}

class EventReferee {
  const EventReferee({
    required this.id,
    required this.slot,
    required this.state,
    required this.proposedSide,
    required this.name,
    this.personId,
    this.clubName,
    this.external = false,
    this.kind = 'federation',
  });
  factory EventReferee.fromJson(Map<String, dynamic> json) => EventReferee(
    id: json['id'] as String,
    slot: json['slot'] as String? ?? 'main',
    state: json['state'] as String? ?? 'confirmed',
    proposedSide: json['proposed_side'] as String? ?? 'team',
    name: json['name'] as String? ?? '',
    personId: json['person_id'] as String?,
    clubName: json['club_name'] as String?,
    external: json['external'] == true,
    kind: json['kind'] as String? ?? 'federation',
  );

  /// federation (förbundsdomare) or club (föreningsdomare).
  final String kind;
  final String id, slot, state, proposedSide, name;
  final String? personId, clubName;
  final bool external;
}

class EventRefereeView {
  const EventRefereeView({
    required this.slots,
    required this.canManage,
    required this.referees,
    this.refereeKind,
    this.canManageClubReferees = false,
    this.controlQuestions = const [],
  });
  factory EventRefereeView.fromJson(Map<String, dynamic> json) =>
      EventRefereeView(
        controlQuestions: [
          for (final row in _maps(json['control_questions']))
            (
              id: row['id'] as String,
              slot: row['slot'] as String? ?? 'main',
              name: row['name'] as String? ?? '',
            ),
        ],
        slots: (json['slots'] as num?)?.toInt() ?? 0,
        canManage: json['can_manage'] == true,
        refereeKind: json['referee_kind'] as String?,
        canManageClubReferees: json['can_manage_club_referees'] == true,
        referees: [
          for (final row
              in (json['referees'] as List? ?? const []).whereType<Map>().map(
                (row) => row.cast<String, dynamic>(),
              ))
            EventReferee.fromJson(row),
        ],
      );
  final int slots;
  final bool canManage;
  final List<EventReferee> referees;

  /// REF-02: federation, club or none; null when not chosen.
  final String? refereeKind;

  /// The domaransvarig: assigns club referees and answers their sign-ups.
  final bool canManageClubReferees;

  /// REF-02: the domaransvarig asks the team's leaders whether a club
  /// referee refereed the match.
  final List<({String id, String slot, String name})> controlQuestions;

  EventReferee? inSlot(String slot) =>
      referees.where((referee) => referee.slot == slot).firstOrNull;
}

class RefereeCandidate {
  const RefereeCandidate({
    required this.personId,
    required this.name,
    required this.clubName,
    required this.confirmable,
    this.teamName,
  });
  factory RefereeCandidate.fromJson(Map<String, dynamic> json) =>
      RefereeCandidate(
        personId: json['person_id'] as String,
        name: json['name'] as String? ?? '',
        clubName: json['club_name'] as String? ?? '',
        teamName: json['team_name'] as String?,
        confirmable: json['confirmable'] == true,
      );
  final String personId, name, clubName;
  final String? teamName;

  /// Someone (the referee or the club's assigner) confirms; otherwise the
  /// referee is confirmed at once.
  final bool confirmable;
}

/// A match as referees see it: no players, no notes.
class RefereeMatch {
  const RefereeMatch({
    required this.eventId,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.teamName,
    required this.clubName,
    required this.slotCount,
    this.opponentName,
    this.homeAway,
    this.location,
    this.taken = const {},
  });
  factory RefereeMatch.fromJson(Map<String, dynamic> json) => RefereeMatch(
    eventId: json['event_id'] as String,
    title: json['title'] as String? ?? '',
    startsAt: _time(json['starts_at']) ?? DateTime.now(),
    endsAt: _time(json['ends_at']) ?? DateTime.now(),
    teamName: json['team_name'] as String? ?? '',
    clubName: json['club_name'] as String? ?? '',
    slotCount: (json['referee_slots'] as num?)?.toInt() ?? 0,
    opponentName: json['opponent_name'] as String?,
    homeAway: json['home_away'] as String?,
    location: json['location'] as String?,
    taken: {
      for (final row
          in (json['taken'] as List? ?? const []).whereType<Map>().map(
            (row) => row.cast<String, dynamic>(),
          ))
        row['slot'] as String: row['state'] as String? ?? '',
    },
  );
  final String eventId, title, teamName, clubName;
  final DateTime startsAt, endsAt;

  /// How many referees the team wants; 0 when not chosen yet.
  final int slotCount;
  final String? opponentName, homeAway, location;

  /// Places with a referee or a pending request, and their state.
  final Map<String, String> taken;

  /// The places a referee can offer for: the team's chosen number, at least
  /// the first, minus those already taken.
  List<String> get openSlots => [
    for (final slot in refereeSlots.take(slotCount.clamp(1, 3)))
      if (!taken.containsKey(slot)) slot,
  ];

  /// "J (IF Eksjö Fotboll) – Vetlanda FF" with home and away in order.
  String get matchup {
    final team = '$teamName ($clubName)';
    final opponent = opponentName;
    if (opponent == null || opponent.trim().isEmpty) return team;
    return homeAway == 'away' ? '$opponent – $team' : '$team – $opponent';
  }
}

class RefereeAssignment {
  const RefereeAssignment({
    required this.referee,
    required this.match,
    required this.awaitingMe,
  });
  factory RefereeAssignment.fromJson(Map<String, dynamic> json) =>
      RefereeAssignment(
        referee: EventReferee.fromJson(json),
        match: RefereeMatch.fromJson(
          (json['match'] as Map).cast<String, dynamic>(),
        ),
        awaitingMe: json['awaiting_me'] == true,
      );
  final EventReferee referee;
  final RefereeMatch match;

  /// A team asked: the referee (or the assigner) answers.
  final bool awaitingMe;
}

class RefereePerson {
  const RefereePerson({
    required this.personId,
    required this.name,
    required this.clubName,
    required this.self,
  });
  factory RefereePerson.fromJson(Map<String, dynamic> json) => RefereePerson(
    personId: json['person_id'] as String,
    name: json['name'] as String? ?? '',
    clubName: json['club_name'] as String? ?? '',
    self: json['self'] == true,
  );
  final String personId, name, clubName;
  final bool self;
}

String refereeKindLabel(String? kind) => switch (kind) {
  'federation' => 'Förbundsdomare',
  'club' => 'Föreningsdomare',
  'none' => 'Ingen domare',
  _ => 'Ej vald',
};

/// REF-02: a club referee with what the domaransvarig needs to choose.
class ClubRefereeInfo {
  const ClubRefereeInfo({
    required this.personId,
    required this.name,
    required this.seasonCount,
    this.age,
    this.trainedOn,
    this.validUntil,
    this.ageOk,
    this.clash = false,
  });
  factory ClubRefereeInfo.fromJson(Map<String, dynamic> json) =>
      ClubRefereeInfo(
        personId: json['person_id'] as String,
        name: json['name'] as String? ?? '',
        seasonCount: (json['season_count'] as num?)?.toInt() ?? 0,
        age: (json['age'] as num?)?.toInt(),
        trainedOn: _time(json['trained_on']),
        validUntil: _time(json['valid_until']),
        ageOk: json['age_ok'] as bool?,
        clash: json['clash'] == true,
      );
  final String personId, name;
  final int seasonCount;
  final int? age;
  final DateTime? trainedOn, validUntil;

  /// At least three years older than the team's players; null unknown.
  final bool? ageOk;

  /// Has something else at the time (own team or another assignment).
  final bool clash;
}

class ClubBoardMatch {
  const ClubBoardMatch({
    required this.match,
    required this.teamId,
    required this.referees,
    this.refereeKind,
  });
  factory ClubBoardMatch.fromJson(Map<String, dynamic> json) => ClubBoardMatch(
    match: RefereeMatch.fromJson(json),
    teamId: json['team_id'] as String? ?? '',
    refereeKind: json['referee_kind'] as String?,
    referees: [
      for (final row
          in (json['referees'] as List? ?? const []).whereType<Map>().map(
            (row) => row.cast<String, dynamic>(),
          ))
        EventReferee.fromJson(row),
    ],
  );
  final RefereeMatch match;
  final String teamId;
  final String? refereeKind;
  final List<EventReferee> referees;

  /// Places without a confirmed referee.
  int get missing =>
      match.slotCount.clamp(refereeKind == 'club' ? 1 : 0, 3) -
      referees.where((referee) => referee.state == 'confirmed').length;
}

class TeamRefereeDefault {
  const TeamRefereeDefault({
    required this.teamId,
    required this.teamName,
    this.kind,
    this.slotCount = 1,
    this.homeOnly = true,
  });
  factory TeamRefereeDefault.fromJson(Map<String, dynamic> json) =>
      TeamRefereeDefault(
        teamId: json['team_id'] as String,
        teamName: json['team_name'] as String? ?? '',
        kind: json['referee_kind'] as String?,
        slotCount: (json['slot_count'] as num?)?.toInt() ?? 1,
        homeOnly: json['home_only'] != false,
      );
  final String teamId, teamName;
  final String? kind;
  final int slotCount;
  final bool homeOnly;
}

class ClubPerson {
  const ClubPerson({
    required this.personId,
    required this.name,
    this.age,
    this.teamNames,
    this.clubReferee = false,
  });
  factory ClubPerson.fromJson(Map<String, dynamic> json) => ClubPerson(
    personId: json['person_id'] as String,
    name: json['name'] as String? ?? '',
    age: (json['age'] as num?)?.toInt(),
    teamNames: json['team_names'] as String?,
    clubReferee: json['club_referee'] == true,
  );
  final String personId, name;
  final int? age;
  final String? teamNames;
  final bool clubReferee;
}

class ClubRefereeBoard {
  const ClubRefereeBoard({
    required this.matches,
    required this.referees,
    required this.defaults,
    required this.coordinators,
    required this.canAppointCoordinators,
  });
  factory ClubRefereeBoard.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> rows(String key) => [
      for (final row in (json[key] as List? ?? const []).whereType<Map>())
        row.cast<String, dynamic>(),
    ];
    return ClubRefereeBoard(
      matches: [
        for (final row in rows('matches')) ClubBoardMatch.fromJson(row),
      ],
      referees: [
        for (final row in rows('referees')) ClubRefereeInfo.fromJson(row),
      ],
      defaults: [
        for (final row in rows('defaults')) TeamRefereeDefault.fromJson(row),
      ],
      coordinators: [
        for (final row in rows('coordinators')) ClubPerson.fromJson(row),
      ],
      canAppointCoordinators: json['can_appoint_coordinators'] == true,
    );
  }
  final List<ClubBoardMatch> matches;
  final List<ClubRefereeInfo> referees;
  final List<TeamRefereeDefault> defaults;
  final List<ClubPerson> coordinators;
  final bool canAppointCoordinators;
}

/// An open place on the own club's match, for one club referee.
class OpenClubMatch {
  const OpenClubMatch({
    required this.match,
    required this.personId,
    required this.personName,
    this.ageOk,
    this.clash = false,
  });
  factory OpenClubMatch.fromJson(Map<String, dynamic> json) => OpenClubMatch(
    match: RefereeMatch.fromJson(json),
    personId: json['person_id'] as String,
    personName: json['person_name'] as String? ?? '',
    ageOk: json['age_ok'] as bool?,
    clash: json['clash'] == true,
  );
  final RefereeMatch match;
  final String personId, personName;
  final bool? ageOk;
  final bool clash;
}

class RefereeSummary {
  const RefereeSummary({
    this.clubReferee = false,
    this.coordinatorClubs = const [],
    this.openCount = 0,
  });
  factory RefereeSummary.fromJson(Map<String, dynamic> json) => RefereeSummary(
    clubReferee: json['club_referee'] == true,
    coordinatorClubs: [
      for (final row
          in (json['coordinator_clubs'] as List? ?? const [])
              .whereType<Map>()
              .map((row) => row.cast<String, dynamic>()))
        (
          id: row['club_id'] as String,
          name: row['club_name'] as String? ?? '',
          canManage: row['can_manage'] != false,
          canPay: row['can_pay'] == true,
          pendingReports: _int(row['pending_reports']),
        ),
    ],
    openCount: (json['open_count'] as num?)?.toInt() ?? 0,
  );

  /// The person, or a child they answer for, is a club referee.
  final bool clubReferee;

  /// Clubs where the person is domaransvarig or pays referees.
  final List<
    ({String id, String name, bool canManage, bool canPay, int pendingReports})
  >
  coordinatorClubs;
  final int openCount;
}

/// REF-02 phase 2: a club referee's report for a played match.
class ClubRefereeReport {
  const ClubRefereeReport({
    required this.id,
    required this.slot,
    required this.name,
    required this.amount,
    required this.state,
    required this.match,
    this.personId,
    this.refereeNote,
    this.controlState,
    this.controlNote,
    this.rejectReason,
    this.payoutId,
  });
  factory ClubRefereeReport.fromJson(Map<String, dynamic> json) =>
      ClubRefereeReport(
        id: json['id'] as String,
        slot: json['slot'] as String? ?? 'main',
        name: json['name'] as String? ?? '',
        amount: _int(json['amount']),
        state: json['state'] as String? ?? 'pending',
        match: RefereeMatch.fromJson(
          (json['match'] as Map? ?? const {'event_id': ''})
              .cast<String, dynamic>(),
        ),
        personId: json['person_id'] as String?,
        refereeNote: json['referee_note'] as String?,
        controlState: json['control_state'] as String?,
        controlNote: json['control_note'] as String?,
        rejectReason: json['reject_reason'] as String?,
        payoutId: json['payout_id'] as String?,
      );
  final String id, slot, name;
  final int amount;

  /// pending, approved, rejected or paid.
  final String state;
  final RefereeMatch match;
  final String? personId, refereeNote, rejectReason, payoutId;

  /// asked, confirmed or denied by the team's leader; null when not asked.
  final String? controlState;
  final String? controlNote;

  /// Not yet on a payout list: can be decided and its amount changed.
  bool get open => payoutId == null && state != 'paid';
}

String refereeReportStateLabel(String state) => switch (state) {
  'pending' => 'Att godkänna',
  'approved' => 'Godkänd',
  'rejected' => 'Inte godkänd',
  'paid' => 'Utbetald',
  _ => state,
};

class ClubRefereeReports {
  const ClubRefereeReports({
    this.reports = const [],
    this.counts = const {},
    this.canManage = false,
    this.canPay = false,
  });
  factory ClubRefereeReports.fromJson(Map<String, dynamic> json) =>
      ClubRefereeReports(
        reports: [
          for (final row in _maps(json['reports']))
            ClubRefereeReport.fromJson(row),
        ],
        counts: {
          for (final entry in (json['counts'] as Map? ?? const {}).entries)
            entry.key as String: _int(entry.value),
        },
        canManage: json['can_manage'] == true,
        canPay: json['can_pay'] == true,
      );
  final List<ClubRefereeReport> reports;
  final Map<String, int> counts;
  final bool canManage, canPay;
}

/// A fee for the main referee and for assistants; null when not set.
class RefereeFee {
  const RefereeFee({
    this.teamId,
    required this.name,
    this.main,
    this.assistant,
  });
  final String? teamId;
  final String name;
  final int? main, assistant;
}

class ClubRefereeFees {
  const ClubRefereeFees({required this.club, this.teams = const []});
  factory ClubRefereeFees.fromJson(Map<String, dynamic> json) {
    final club = (json['club'] as Map?)?.cast<String, dynamic>();
    return ClubRefereeFees(
      club: RefereeFee(
        name: 'Hela klubben',
        main: (club?['fee_main'] as num?)?.toInt(),
        assistant: (club?['fee_assistant'] as num?)?.toInt(),
      ),
      teams: [
        for (final row in _maps(json['teams']))
          RefereeFee(
            teamId: row['team_id'] as String,
            name: row['team_name'] as String? ?? '',
            main: (row['fee_main'] as num?)?.toInt(),
            assistant: (row['fee_assistant'] as num?)?.toInt(),
          ),
      ],
    );
  }
  final RefereeFee club;
  final List<RefereeFee> teams;
}

class RefereePayoutLine {
  const RefereePayoutLine({
    required this.id,
    required this.name,
    required this.reportCount,
    required this.amount,
    required this.yearTotal,
    this.personId,
    this.age,
    this.guardians,
  });
  factory RefereePayoutLine.fromJson(Map<String, dynamic> json) =>
      RefereePayoutLine(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        reportCount: _int(json['report_count']),
        amount: _int(json['amount']),
        yearTotal: _int(json['year_total']),
        personId: json['person_id'] as String?,
        age: (json['age'] as num?)?.toInt(),
        guardians: json['guardians'] as String?,
      );
  final String id, name;
  final int reportCount, amount, yearTotal;
  final String? personId;
  final int? age;

  /// Under 18: the guardians, who may receive the pay.
  final String? guardians;
}

class RefereePayoutRow {
  const RefereePayoutRow({
    required this.name,
    required this.slot,
    required this.amount,
    required this.startsAt,
    required this.teamName,
    this.opponentName,
  });
  factory RefereePayoutRow.fromJson(Map<String, dynamic> json) =>
      RefereePayoutRow(
        name: json['name'] as String? ?? '',
        slot: json['slot'] as String? ?? 'main',
        amount: _int(json['amount']),
        startsAt: _time(json['starts_at']) ?? DateTime.now(),
        teamName: json['team_name'] as String? ?? '',
        opponentName: json['opponent_name'] as String?,
      );
  final String name, slot, teamName;
  final int amount;
  final DateTime startsAt;
  final String? opponentName;
}

class RefereePayout {
  const RefereePayout({
    required this.id,
    required this.throughDate,
    required this.state,
    required this.total,
    required this.lineCount,
    this.paidAt,
    this.limit = 0,
    this.lines = const [],
    this.rows = const [],
  });
  factory RefereePayout.fromJson(Map<String, dynamic> json) => RefereePayout(
    id: json['id'] as String,
    throughDate: _time(json['through_date']) ?? DateTime.now(),
    state: json['state'] as String? ?? 'draft',
    total: _int(json['total']),
    lineCount: _int(json['line_count']),
    paidAt: _time(json['paid_at']),
    limit: _int(json['limit']),
    lines: [
      for (final row in _maps(json['lines'])) RefereePayoutLine.fromJson(row),
    ],
    rows: [
      for (final row in _maps(json['reports'])) RefereePayoutRow.fromJson(row),
    ],
  );
  final String id;
  final DateTime throughDate;

  /// draft (not paid yet) or paid.
  final String state;
  final int total, lineCount;
  final DateTime? paidAt;

  /// The year's guide: half a prisbasbelopp.
  final int limit;
  final List<RefereePayoutLine> lines;
  final List<RefereePayoutRow> rows;
}

class RefereePayouts {
  const RefereePayouts({
    this.payouts = const [],
    this.readyCount = 0,
    this.readyTotal = 0,
    this.payers = const [],
    this.canAppointPayers = false,
  });
  factory RefereePayouts.fromJson(Map<String, dynamic> json) => RefereePayouts(
    payouts: [
      for (final row in _maps(json['payouts'])) RefereePayout.fromJson(row),
    ],
    readyCount: _int(json['ready_count']),
    readyTotal: _int(json['ready_total']),
    payers: [for (final row in _maps(json['payers'])) ClubPerson.fromJson(row)],
    canAppointPayers: json['can_appoint_payers'] == true,
  );
  final List<RefereePayout> payouts;

  /// Approved and not on a list yet.
  final int readyCount, readyTotal;
  final List<ClubPerson> payers;
  final bool canAppointPayers;
}

/// A club referee's own pay (a guardian sees the child's).
class MyRefereePay {
  const MyRefereePay({
    required this.personId,
    required this.name,
    required this.year,
    required this.yearTotal,
    required this.limit,
    required this.canNote,
    this.reports = const [],
  });
  factory MyRefereePay.fromJson(Map<String, dynamic> json) => MyRefereePay(
    personId: json['person_id'] as String,
    name: json['name'] as String? ?? '',
    year: _int(json['year']),
    yearTotal: _int(json['year_total']),
    limit: _int(json['limit']),
    canNote: json['can_note'] == true,
    reports: [
      for (final row in _maps(json['reports'])) ClubRefereeReport.fromJson(row),
    ],
  );
  final String personId, name;
  final int year, yearTotal, limit;
  final bool canNote;
  final List<ClubRefereeReport> reports;
}

abstract interface class RefereeServices {
  Future<EventRefereeView> getEventReferees(String eventId);
  Future<void> setSlots(String eventId, int count);
  Future<List<RefereeCandidate>> searchReferees(String query);

  /// A referee in TeamZone ([personId]) or one written in ([writtenName]).
  Future<void> propose(
    String eventId,
    String slot, {
    String? personId,
    String? writtenName,
  });
  Future<void> request(String eventId, String slot, String personId);
  Future<void> respond(String refereeId, bool accept);
  Future<void> withdraw(String refereeId);
  Future<List<RefereeMatch>> searchMatches(
    String query,
    DateTime from,
    DateTime to,
  );
  Future<List<RefereePerson>> myRefereePeople();
  Future<List<RefereeAssignment>> myAssignments();

  // REF-02: club referees and the domaransvarig.
  Future<void> setKind(String eventId, String kind);
  Future<int> saveTeamDefault(
    String teamId,
    String kind,
    int slotCount,
    bool homeOnly,
  );
  Future<void> setClubReferee(
    String clubId,
    String personId,
    bool enabled, {
    DateTime? trainedOn,
    DateTime? validUntil,
  });
  Future<void> setCoordinator(String clubId, String personId, bool enabled);
  Future<ClubRefereeBoard> board(String clubId, DateTime from, DateTime to);
  Future<List<ClubRefereeInfo>> candidates(String eventId);
  Future<List<ClubPerson>> searchClubPeople(String clubId, String query);
  Future<List<OpenClubMatch>> openClubMatches();
  Future<void> requestClub(String eventId, String slot, String personId);
  Future<RefereeSummary> summary();

  // REF-02 phase 2: fees, reports and payout lists.
  Future<ClubRefereeFees> fees(String clubId);
  Future<int> saveFee(String clubId, String? teamId, int? main, int? assistant);
  Future<ClubRefereeReports> reports(String clubId, {String? state});
  Future<void> askControl(String reportId);
  Future<void> answerControl(String reportId, bool confirmed, {String? note});
  Future<int> decideReports(
    String clubId,
    List<String> reportIds,
    bool approve, {
    String? reason,
  });
  Future<void> setReportAmount(String reportId, int amount);
  Future<void> noteReport(String reportId, String note);
  Future<List<MyRefereePay>> myPay();
  Future<String> createPayout(String clubId, DateTime throughDate);
  Future<RefereePayout> payout(String payoutId);
  Future<RefereePayouts> payouts(String clubId);
  Future<void> markPayoutPaid(String payoutId);
  Future<void> cancelPayout(String payoutId);
  Future<void> setPayer(String clubId, String personId, bool enabled);
}

class UnconfiguredRefereeServices implements RefereeServices {
  const UnconfiguredRefereeServices();
  Future<T> _fail<T>() => Future.error(StateError('not_configured'));
  @override
  Future<EventRefereeView> getEventReferees(String eventId) => _fail();
  @override
  Future<void> setSlots(String eventId, int count) => _fail();
  @override
  Future<List<RefereeCandidate>> searchReferees(String query) async => const [];
  @override
  Future<void> propose(
    String eventId,
    String slot, {
    String? personId,
    String? writtenName,
  }) => _fail();
  @override
  Future<void> request(String eventId, String slot, String personId) => _fail();
  @override
  Future<void> respond(String refereeId, bool accept) => _fail();
  @override
  Future<void> withdraw(String refereeId) => _fail();
  @override
  Future<List<RefereeMatch>> searchMatches(
    String query,
    DateTime from,
    DateTime to,
  ) async => const [];
  @override
  Future<List<RefereePerson>> myRefereePeople() async => const [];
  @override
  Future<List<RefereeAssignment>> myAssignments() async => const [];
  @override
  Future<void> setKind(String eventId, String kind) => _fail();
  @override
  Future<int> saveTeamDefault(
    String teamId,
    String kind,
    int slotCount,
    bool homeOnly,
  ) => _fail();
  @override
  Future<void> setClubReferee(
    String clubId,
    String personId,
    bool enabled, {
    DateTime? trainedOn,
    DateTime? validUntil,
  }) => _fail();
  @override
  Future<void> setCoordinator(String clubId, String personId, bool enabled) =>
      _fail();
  @override
  Future<ClubRefereeBoard> board(String clubId, DateTime from, DateTime to) =>
      _fail();
  @override
  Future<List<ClubRefereeInfo>> candidates(String eventId) async => const [];
  @override
  Future<List<ClubPerson>> searchClubPeople(
    String clubId,
    String query,
  ) async => const [];
  @override
  Future<List<OpenClubMatch>> openClubMatches() async => const [];
  @override
  Future<void> requestClub(String eventId, String slot, String personId) =>
      _fail();
  @override
  Future<RefereeSummary> summary() async => const RefereeSummary();

  @override
  Future<ClubRefereeFees> fees(String clubId) => _fail();
  @override
  Future<int> saveFee(
    String clubId,
    String? teamId,
    int? main,
    int? assistant,
  ) => _fail();
  @override
  Future<ClubRefereeReports> reports(String clubId, {String? state}) => _fail();
  @override
  Future<void> askControl(String reportId) => _fail();
  @override
  Future<void> answerControl(String reportId, bool confirmed, {String? note}) =>
      _fail();
  @override
  Future<int> decideReports(
    String clubId,
    List<String> reportIds,
    bool approve, {
    String? reason,
  }) => _fail();
  @override
  Future<void> setReportAmount(String reportId, int amount) => _fail();
  @override
  Future<void> noteReport(String reportId, String note) => _fail();
  @override
  Future<List<MyRefereePay>> myPay() async => const [];
  @override
  Future<String> createPayout(String clubId, DateTime throughDate) => _fail();
  @override
  Future<RefereePayout> payout(String payoutId) => _fail();
  @override
  Future<RefereePayouts> payouts(String clubId) => _fail();
  @override
  Future<void> markPayoutPaid(String payoutId) => _fail();
  @override
  Future<void> cancelPayout(String payoutId) => _fail();
  @override
  Future<void> setPayer(String clubId, String personId, bool enabled) =>
      _fail();
}

class SupabaseRefereeServices implements RefereeServices {
  SupabaseRefereeServices(this._client);
  final SupabaseClient _client;

  Future<Object?> _rpc(String name, [Map<String, dynamic>? params]) =>
      _client.schema('api').rpc<Object?>(name, params: params);

  List<Map<String, dynamic>> _rows(Object? value) => [
    if (value is List)
      for (final row in value.whereType<Map>()) row.cast<String, dynamic>(),
  ];

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  @override
  Future<EventRefereeView> getEventReferees(String eventId) async {
    final value = await _rpc('get_event_referees', {
      'target_event_id': eventId,
    });
    if (value is! Map) throw StateError('invalid_response');
    return EventRefereeView.fromJson(value.cast<String, dynamic>());
  }

  @override
  Future<void> setSlots(String eventId, int count) async {
    await _rpc('set_event_referee_slots', {
      'target_event_id': eventId,
      'slot_count': count,
    });
  }

  @override
  Future<List<RefereeCandidate>> searchReferees(String query) async => [
    for (final row in _rows(
      await _rpc('search_referees', {'search_text': query}),
    ))
      RefereeCandidate.fromJson(row),
  ];

  @override
  Future<void> propose(
    String eventId,
    String slot, {
    String? personId,
    String? writtenName,
  }) async {
    await _rpc('propose_event_referee', {
      'target_event_id': eventId,
      'target_slot': slot,
      'target_person_id': personId,
      'written_name': writtenName,
    });
  }

  @override
  Future<void> request(String eventId, String slot, String personId) async {
    await _rpc('request_event_referee', {
      'target_event_id': eventId,
      'target_slot': slot,
      'target_person_id': personId,
    });
  }

  @override
  Future<void> respond(String refereeId, bool accept) async {
    await _rpc('respond_event_referee', {
      'target_referee_id': refereeId,
      'accept': accept,
    });
  }

  @override
  Future<void> withdraw(String refereeId) async {
    await _rpc('withdraw_event_referee', {'target_referee_id': refereeId});
  }

  @override
  Future<List<RefereeMatch>> searchMatches(
    String query,
    DateTime from,
    DateTime to,
  ) async => [
    for (final row in _rows(
      await _rpc('search_referee_matches', {
        'search_text': query,
        'from_date': _date(from),
        'to_date': _date(to),
      }),
    ))
      RefereeMatch.fromJson(row),
  ];

  @override
  Future<List<RefereePerson>> myRefereePeople() async => [
    for (final row in _rows(await _rpc('list_my_referee_people')))
      RefereePerson.fromJson(row),
  ];

  @override
  Future<List<RefereeAssignment>> myAssignments() async => [
    for (final row in _rows(await _rpc('list_my_referee_assignments')))
      RefereeAssignment.fromJson(row),
  ];

  @override
  Future<void> setKind(String eventId, String kind) async {
    await _rpc('set_event_referee_kind', {
      'target_event_id': eventId,
      'kind': kind,
    });
  }

  @override
  Future<int> saveTeamDefault(
    String teamId,
    String kind,
    int slotCount,
    bool homeOnly,
  ) async {
    final value = await _rpc('save_team_referee_default', {
      'target_team_id': teamId,
      'kind': kind,
      'slot_count': slotCount,
      'home_only': homeOnly,
    });
    return value is num ? value.toInt() : 0;
  }

  @override
  Future<void> setClubReferee(
    String clubId,
    String personId,
    bool enabled, {
    DateTime? trainedOn,
    DateTime? validUntil,
  }) async {
    await _rpc('set_club_referee', {
      'target_club_id': clubId,
      'target_person_id': personId,
      'enabled': enabled,
      'trained_on': trainedOn == null ? null : _date(trainedOn),
      'valid_until': validUntil == null ? null : _date(validUntil),
    });
  }

  @override
  Future<void> setCoordinator(
    String clubId,
    String personId,
    bool enabled,
  ) async {
    await _rpc('set_club_referee_coordinator', {
      'target_club_id': clubId,
      'target_person_id': personId,
      'enabled': enabled,
    });
  }

  @override
  Future<ClubRefereeBoard> board(
    String clubId,
    DateTime from,
    DateTime to,
  ) async {
    final value = await _rpc('get_club_referee_board', {
      'target_club_id': clubId,
      'from_date': _date(from),
      'to_date': _date(to),
    });
    if (value is! Map) throw StateError('invalid_response');
    return ClubRefereeBoard.fromJson(value.cast<String, dynamic>());
  }

  @override
  Future<List<ClubRefereeInfo>> candidates(String eventId) async => [
    for (final row in _rows(
      await _rpc('list_club_referee_candidates', {'target_event_id': eventId}),
    ))
      ClubRefereeInfo.fromJson(row),
  ];

  @override
  Future<List<ClubPerson>> searchClubPeople(
    String clubId,
    String query,
  ) async => [
    for (final row in _rows(
      await _rpc('search_club_people_for_referees', {
        'target_club_id': clubId,
        'search_text': query,
      }),
    ))
      ClubPerson.fromJson(row),
  ];

  @override
  Future<List<OpenClubMatch>> openClubMatches() async => [
    for (final row in _rows(await _rpc('list_open_club_matches')))
      OpenClubMatch.fromJson(row),
  ];

  @override
  Future<void> requestClub(String eventId, String slot, String personId) async {
    await _rpc('request_club_referee', {
      'target_event_id': eventId,
      'target_slot': slot,
      'target_person_id': personId,
    });
  }

  @override
  Future<RefereeSummary> summary() async {
    final value = await _rpc('get_my_referee_summary');
    return value is Map
        ? RefereeSummary.fromJson(value.cast<String, dynamic>())
        : const RefereeSummary();
  }

  Map<String, dynamic> _map(Object? value) =>
      value is Map ? value.cast<String, dynamic>() : const {};

  @override
  Future<ClubRefereeFees> fees(String clubId) async => ClubRefereeFees.fromJson(
    _map(await _rpc('get_club_referee_fees', {'target_club_id': clubId})),
  );

  @override
  Future<int> saveFee(
    String clubId,
    String? teamId,
    int? main,
    int? assistant,
  ) async => _int(
    await _rpc('save_club_referee_fee', {
      'target_club_id': clubId,
      'target_team_id': teamId,
      'fee_main': main,
      'fee_assistant': assistant,
    }),
  );

  @override
  Future<ClubRefereeReports> reports(String clubId, {String? state}) async =>
      ClubRefereeReports.fromJson(
        _map(
          await _rpc('list_club_referee_reports', {
            'target_club_id': clubId,
            'target_state': state,
          }),
        ),
      );

  @override
  Future<void> askControl(String reportId) async {
    await _rpc('ask_club_referee_control', {'target_report_id': reportId});
  }

  @override
  Future<void> answerControl(
    String reportId,
    bool confirmed, {
    String? note,
  }) async {
    await _rpc('answer_club_referee_control', {
      'target_report_id': reportId,
      'confirmed': confirmed,
      'note': note,
    });
  }

  @override
  Future<int> decideReports(
    String clubId,
    List<String> reportIds,
    bool approve, {
    String? reason,
  }) async => _int(
    await _rpc('decide_club_referee_reports', {
      'target_club_id': clubId,
      'report_ids': reportIds,
      'approve': approve,
      'reason': reason,
    }),
  );

  @override
  Future<void> setReportAmount(String reportId, int amount) async {
    await _rpc('set_club_referee_report_amount', {
      'target_report_id': reportId,
      'amount': amount,
    });
  }

  @override
  Future<void> noteReport(String reportId, String note) async {
    await _rpc('note_club_referee_report', {
      'target_report_id': reportId,
      'note': note,
    });
  }

  @override
  Future<List<MyRefereePay>> myPay() async => [
    for (final row in _rows(await _rpc('list_my_referee_reports')))
      MyRefereePay.fromJson(row),
  ];

  @override
  Future<String> createPayout(String clubId, DateTime throughDate) async =>
      await _rpc('create_club_referee_payout', {
            'target_club_id': clubId,
            'through_date': _date(throughDate),
          })
          as String;

  @override
  Future<RefereePayout> payout(String payoutId) async => RefereePayout.fromJson(
    _map(await _rpc('get_club_referee_payout', {'target_payout_id': payoutId})),
  );

  @override
  Future<RefereePayouts> payouts(String clubId) async =>
      RefereePayouts.fromJson(
        _map(
          await _rpc('list_club_referee_payouts', {'target_club_id': clubId}),
        ),
      );

  @override
  Future<void> markPayoutPaid(String payoutId) async {
    await _rpc('mark_club_referee_payout_paid', {'target_payout_id': payoutId});
  }

  @override
  Future<void> cancelPayout(String payoutId) async {
    await _rpc('cancel_club_referee_payout', {'target_payout_id': payoutId});
  }

  @override
  Future<void> setPayer(String clubId, String personId, bool enabled) async {
    await _rpc('set_club_referee_payer', {
      'target_club_id': clubId,
      'target_person_id': personId,
      'enabled': enabled,
    });
  }
}
