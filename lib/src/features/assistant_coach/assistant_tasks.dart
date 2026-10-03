import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/product_route_contract.dart';
import '../../core/identity/identity_models.dart';
import '../calendar/calendar_models.dart';
import '../calendar/preparation_services.dart';
import 'assistant_preparation_checklist.dart';
import 'assistant_task_preferences.dart';
import '../overview/overview_models.dart';
import '../overview/overview_services.dart';

/// Page context is presentation only. Every read and action is authorized by
/// the existing domain endpoints, independently of the assistant signal gate.
class AssistantPageContext {
  const AssistantPageContext(this.location);
  final String location;

  Uri? get _uri =>
      Uri.tryParse(ProductRouteContract.canonicalizeLocation(location));
  String get path => _uri?.path ?? location;

  String? get eventId {
    final segments = _uri?.pathSegments ?? const <String>[];
    return segments.length == 3 &&
            segments[0] == 'calendar' &&
            segments[1] == 'event' &&
            segments[2].isNotEmpty
        ? segments[2]
        : null;
  }

  String get label {
    if (eventId != null) return 'Den här aktiviteten';
    if (path.startsWith('${ProductRouteContract.team}/member/')) return 'Laget';
    return switch (path) {
      '/home' => 'Överblick',
      '/calendar' => 'Kalendern',
      '/team' => 'Laget',
      '/statistics' => 'Statistik',
      '/development' => 'Utveckling',
      '/inbox' => 'Inkorgen',
      _ => 'Aktuellt lag',
    };
  }

  bool get isHome => path == ProductRouteContract.home;

  bool isRelevant(AssistantTask task) {
    final currentEventId = eventId;
    if (currentEventId != null) {
      return task.eventId == currentEventId ||
          task.overlappingEvent?.id == currentEventId;
    }
    return switch (path) {
      ProductRouteContract.calendar => true,
      ProductRouteContract.team => {
        'pending_callups',
        'missing_callups',
        'missing_attendance',
      }.contains(task.task.kind),
      _ when path.startsWith('${ProductRouteContract.team}/member/') => {
        'pending_callups',
        'missing_callups',
        'missing_attendance',
      }.contains(task.task.kind),
      ProductRouteContract.statistics => {
        'missing_attendance',
        'missing_match_result',
        'missing_match_report',
      }.contains(task.task.kind),
      _ => false,
    };
  }
}

class AssistantTask {
  const AssistantTask({
    required this.context,
    required this.task,
    required this.eventId,
    required this.generatedAt,
    required this.stale,
    this.eventTitle,
    this.startsAt,
    this.endsAt,
    this.overlappingEvent,
    this.eventDetails,
    this.overlappingContext,
    this.response,
    this.overlappingResponse,
  });
  final TeamZoneContext context;
  final LeaderHomeTask task;
  final String eventId;
  final DateTime generatedAt;
  final bool stale;
  final String? eventTitle;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final EventDetails? overlappingEvent;
  final EventDetails? eventDetails;
  final TeamZoneContext? overlappingContext;
  final String? response, overlappingResponse;
  bool get isPersonalConflict => task.kind == 'personal_calendar_conflict';
  bool get isImportant {
    if (task.kind == 'calendar_conflict' || isPersonalConflict) return true;
    if (!{
      'pending_callups',
      'missing_callups',
      'unfinished_preparation',
    }.contains(task.kind)) {
      return false;
    }
    final start = startsAt;
    return start != null &&
        !start.isBefore(generatedAt) &&
        !start.isAfter(generatedAt.add(const Duration(days: 1)));
  }

  bool inCategory(String category) => switch (category) {
    'important' => isImportant,
    'preparation' => task.kind == 'unfinished_preparation',
    'matches' =>
      isMatchFollowup ||
          eventDetails?.type == 'match' ||
          overlappingEvent?.type == 'match',
    'training' =>
      eventDetails?.type == 'training' || overlappingEvent?.type == 'training',
    'other' =>
      !isMatchFollowup &&
          !{
            eventDetails?.type,
            overlappingEvent?.type,
          }.any((t) => t == 'match' || t == 'training'),
    _ => true,
  };
  TeamZoneContext contextForEvent(String id) =>
      id == overlappingEvent?.id ? overlappingContext ?? context : context;
  String eventContextLabel(String id) {
    final value = contextForEvent(id);
    return '${value.clubName} · ${value.teamName}';
  }

  String get key =>
      '${context.clubId}:$eventId:${task.kind}'
      '${overlappingEvent == null ? '' : ':${overlappingEvent!.id}'}';
  String get route => Uri(
    path: ProductRouteContract.calendarEvent(eventId),
    queryParameters: {
      'context': context.id,
      'tab': task.kind == 'unfinished_preparation'
          ? 'preparation'
          : isMatchFollowup || task.kind == 'calendar_conflict'
          ? 'info'
          : 'participants',
    },
  ).toString();
  bool get isMatchFollowup =>
      task.kind == 'missing_match_result' ||
      task.kind == 'missing_match_report';
  String get actionLabel => switch (task.kind) {
    'personal_calendar_conflict' => 'Öppna aktivitet och hantera krock',
    'calendar_conflict' => 'Välj aktivitet och ändra tid',
    'unfinished_preparation' => 'Öppna förberedelser',
    'missing_match_result' => 'Registrera resultat',
    'missing_match_report' => 'Skriv matchrapport',
    'pending_callups' => 'Granska och påminn',
    'missing_attendance' => 'Registrera närvaro',
    'missing_callups' => 'Förbered kallelser',
    _ => 'Öppna kallelser',
  };
  String get explanation => switch (task.kind) {
    'personal_calendar_conflict' =>
      'Dina egna kallelser i olika lag överlappar under kommande sju dagar. '
          'Två ja-svar innebär dubbelbokning; ett obesvarat svar innebär en möjlig krock. '
          'Den här jämförelsen är privat för dig och delas inte med lagens ledare.',
    'calendar_conflict' =>
      'Två synliga aktiviteter i laget överlappar i tid under kommande sju dagar. '
          'Det kan vara avsiktligt. Kontrollera tiderna; inga aktiviteter ändras automatiskt.',
    'unfinished_preparation' =>
      '${task.count} befintliga material- eller uppgiftspunkter är inte markerade som klara '
          'inför en aktivitet inom 48 timmar. Kallelser visas separat. '
          'En tom lista betyder inte att alla förberedelser är klara.',
    'missing_match_result' =>
      'Matchens sluttid har passerat under de senaste sju dagarna, men inget '
          'slutresultat är registrerat. Kontrollera först att matchen spelades.',
    'missing_match_report' =>
      'Matchen har ett registrerat slutresultat men saknar skriven matchrapport. '
          'Gäller matcher som slutade under de senaste sju dagarna. Rapporten kan sparas som utkast.',
    'missing_attendance' =>
      '${task.count} accepterade deltagare saknar registrerad närvaro. '
          'Gäller aktiviteter som slutade under de senaste sju dagarna.',
    'missing_callups' =>
      'Aktiviteten börjar inom 48 timmar, är markerad med '
          '”Kallelse behövs” och inga kallelser har skickats. '
          'Uppgiften försvinner när kallelser skickas eller kallelsebehovet stängs av på Info-fliken.',
    _ =>
      '${task.count} kallelser är obesvarade inför en kommande aktivitet. '
          'Granska mottagarna innan du skickar. Utgångna kallelser och personer '
          'som påmints de senaste sex timmarna undantas från utskicket.',
  };

  AssistantTask get overlappingTask => AssistantTask(
    context: context,
    task: task,
    eventId: overlappingEvent!.id,
    generatedAt: generatedAt,
    stale: stale,
    eventTitle: overlappingEvent!.title,
    startsAt: overlappingEvent!.startsAt,
    endsAt: overlappingEvent!.endsAt,
    eventDetails: overlappingEvent,
  );
}

class AssistantTaskSnapshot {
  const AssistantTaskSnapshot(
    this.tasks,
    this.failedContexts, {
    this.personalFailed = false,
    this.settingsFailed = false,
    this.filtersActive = false,
    this.currentTeamOnly = false,
    this.preferences = const AssistantTaskPreferences(),
  });
  final List<AssistantTask> tasks;
  final List<TeamZoneContext> failedContexts;
  final bool personalFailed;
  final bool settingsFailed, filtersActive;
  final bool currentTeamOnly;
  final AssistantTaskPreferences preferences;
}

Future<AssistantTaskSnapshot> loadAssistantTasks({
  required List<TeamZoneContext> contexts,
  TeamZoneContext? activeContext,
  required OverviewServices overview,
  required Future<EventDetails> Function(String) loadEvent,
}) async {
  var preferences = const AssistantTaskPreferences();
  if (overview is AssistantTaskPreferencesServices) {
    try {
      preferences = await (overview as AssistantTaskPreferencesServices)
          .loadAssistantTaskPreferences()
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      return const AssistantTaskSnapshot(
        [],
        [],
        settingsFailed: true,
        preferences: AssistantTaskPreferences(welcomeMessageVisible: false),
      );
    }
  }
  final tasks = <String, AssistantTask>{};
  final failed = <TeamZoneContext>[];
  final leaders = {
    for (final context in contexts)
      if (context.rolePackage == 'leader' &&
          context.teamId != null &&
          (!preferences.currentTeamOnly ||
              (activeContext?.teamId != null &&
                  context.clubId == activeContext!.clubId &&
                  context.teamId == activeContext.teamId)))
        context.id: context,
  };
  // Bound requests: teams are read in order and metadata is shared per event.
  final events = <String, EventDetails>{};
  bool personalFailed = false;
  for (final context in leaders.values) {
    try {
      final home =
          await (overview is FreshLeaderOverviewServices
                  ? (overview as FreshLeaderOverviewServices)
                        .loadFreshLeaderHome(context.id)
                  : overview.loadLeaderHome(context.id))
              .timeout(const Duration(seconds: 15));
      for (final task in home.tasks) {
        if (!preferences.shows(task.kind)) continue;
        final capability = switch (task.kind) {
          'pending_callups' || 'missing_callups' => 'event.squad.manage',
          'missing_attendance' => 'event.attendance.manage',
          'missing_match_result' || 'missing_match_report' => 'match.live',
          'calendar_conflict' => 'event.manage',
          'unfinished_preparation' => 'event.logistics',
          _ => null,
        };
        if (capability == null || !context.can(capability) || task.count <= 0) {
          continue;
        }
        final uri = Uri.tryParse(task.route);
        if (uri == null || uri.hasScheme || uri.hasAuthority) continue;
        final eventId = AssistantPageContext(task.route).eventId;
        if (eventId == null) continue;
        // Resolve the event label through the ordinary authorized event read.
        final event = events[eventId] ??= await loadEvent(
          eventId,
        ).timeout(const Duration(seconds: 15));
        if (event.state == 'cancelled' || event.archivedAt != null) continue;
        if (task.kind == 'missing_callups' && !event.callupsRequired) continue;
        if (task.kind == 'unfinished_preparation' &&
            event.state != 'scheduled') {
          continue;
        }
        EventDetails? overlapping;
        if (task.kind == 'calendar_conflict') {
          final otherId = uri.queryParameters['overlap'];
          if (otherId == null || otherId.isEmpty || otherId == eventId) {
            continue;
          }
          overlapping = events[otherId] ??= await loadEvent(
            otherId,
          ).timeout(const Duration(seconds: 15));
          // Recheck facts after the projection read; a leader may have moved
          // or cancelled either event in the meantime.
          if (event.state != 'scheduled' ||
              overlapping.state != 'scheduled' ||
              overlapping.archivedAt != null ||
              !event.endsAt.isAfter(home.generatedAt) ||
              !overlapping.endsAt.isAfter(home.generatedAt) ||
              !event.startsAt.isBefore(overlapping.endsAt) ||
              !overlapping.startsAt.isBefore(event.endsAt)) {
            continue;
          }
        }
        final item = AssistantTask(
          context: context,
          task: task,
          eventId: eventId,
          generatedAt: home.generatedAt,
          stale: home.isStale,
          eventTitle: event.title,
          startsAt: event.startsAt,
          endsAt: event.endsAt,
          overlappingEvent: overlapping,
          eventDetails: event,
        );
        tasks.putIfAbsent(item.key, () => item);
      }
    } catch (_) {
      // Do not retain a partially read team's tasks on permission/read errors.
      tasks.removeWhere((_, task) => task.context.id == context.id);
      failed.add(context);
    }
  }
  if (overview is PersonalCalendarConflictServices &&
      preferences.shows('personal_calendar_conflict')) {
    final personal = <AssistantTask>[];
    try {
      final value = await (overview as PersonalCalendarConflictServices)
          .loadPersonalCalendarConflicts()
          .timeout(const Duration(seconds: 15));
      final generatedAt = DateTime.parse(value['generated_at'] as String);
      for (final row in (value['tasks'] as List)) {
        final first = Map<String, dynamic>.from(row['first_event'] as Map);
        final second = Map<String, dynamic>.from(row['second_event'] as Map);
        final firstContext = contexts
            .where((c) => c.id == first['context_id'])
            .firstOrNull;
        final secondContext = contexts
            .where((c) => c.id == second['context_id'])
            .firstOrNull;
        if (firstContext == null || secondContext == null) continue;
        if (preferences.currentTeamOnly &&
            !(activeContext?.teamId != null &&
                ((firstContext.clubId == activeContext!.clubId &&
                        firstContext.teamId == activeContext.teamId) ||
                    (secondContext.clubId == activeContext.clubId &&
                        secondContext.teamId == activeContext.teamId)))) {
          continue;
        }
        final a = events[first['event_id']] ??= await loadEvent(
          first['event_id'] as String,
        ).timeout(const Duration(seconds: 15));
        final b = events[second['event_id']] ??= await loadEvent(
          second['event_id'] as String,
        ).timeout(const Duration(seconds: 15));
        if (a.id == b.id ||
            a.state != 'scheduled' ||
            b.state != 'scheduled' ||
            a.archivedAt != null ||
            b.archivedAt != null ||
            !a.endsAt.isAfter(generatedAt) ||
            !b.endsAt.isAfter(generatedAt) ||
            !a.startsAt.isBefore(b.endsAt) ||
            !b.startsAt.isBefore(a.endsAt)) {
          continue;
        }
        personal.add(
          AssistantTask(
            context: firstContext,
            overlappingContext: secondContext,
            task: LeaderHomeTask.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
            eventId: a.id,
            generatedAt: generatedAt,
            stale: false,
            eventTitle: a.title,
            startsAt: a.startsAt,
            endsAt: a.endsAt,
            eventDetails: a,
            overlappingEvent: b,
            response: first['response'] as String,
            overlappingResponse: second['response'] as String,
          ),
        );
      }
      for (final item in personal) {
        tasks[item.key] = item;
      }
    } catch (_) {
      personalFailed = true;
    }
  }
  final sorted = tasks.values.toList()
    ..sort((a, b) {
      int rank(AssistantTask item) => switch (item.task.kind) {
        _ when item.isImportant => 0,
        'missing_attendance' => 1,
        _ => 2,
      };
      final kind = rank(a).compareTo(rank(b));
      if (kind != 0) return kind;
      final date = (a.startsAt ?? a.generatedAt).compareTo(
        b.startsAt ?? b.generatedAt,
      );
      return date != 0 ? date : a.key.compareTo(b.key);
    });
  return AssistantTaskSnapshot(
    sorted,
    failed,
    personalFailed: personalFailed,
    filtersActive:
        preferences.hiddenKinds.isNotEmpty || preferences.currentTeamOnly,
    currentTeamOnly: preferences.currentTeamOnly,
    preferences: preferences,
  );
}

class AssistantTaskSections extends StatefulWidget {
  const AssistantTaskSections({
    super.key,
    required this.contexts,
    required this.activeContext,
    required this.page,
    required this.overview,
    required this.loadEvent,
    required this.onOpen,
    this.preparation,
  });
  final List<TeamZoneContext> contexts;
  final TeamZoneContext activeContext;
  final AssistantPageContext page;
  final OverviewServices overview;
  final Future<EventDetails> Function(String) loadEvent;
  final Future<void> Function(AssistantTask) onOpen;
  final EventPreparationServices? preparation;

  @override
  State<AssistantTaskSections> createState() => _AssistantTaskSectionsState();
}

class _AssistantTaskSectionsState extends State<AssistantTaskSections>
    with WidgetsBindingObserver {
  late Future<AssistantTaskSnapshot> _data;
  bool _opening = false;
  bool _welcomeDismissed = false;
  String _bucket = 'active';
  String _category = 'all';
  final _categoryScroll = ScrollController();
  String? _expandedKey;
  Timer? _wakeTimer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _data = _load();
  }

  Future<AssistantTaskSnapshot> _load() async {
    final result = await loadAssistantTasks(
      contexts: widget.contexts,
      activeContext: widget.activeContext,
      overview: widget.overview,
      loadEvent: widget.loadEvent,
    );
    if (mounted) {
      _wakeTimer?.cancel();
      final wakeTimes =
          result.tasks
              .map((t) => t.task.snoozedUntil)
              .whereType<DateTime>()
              .where((t) => t.isAfter(DateTime.now()))
              .toList()
            ..sort();
      if (wakeTimes.isNotEmpty) {
        _wakeTimer = Timer(
          wakeTimes.first.difference(DateTime.now()) +
              const Duration(seconds: 1),
          () {
            if (mounted) _refresh();
          },
        );
      }
    }
    return result;
  }

  void _refresh() => setState(() {
    _data = _load();
  });
  @override
  void didUpdateWidget(covariant AssistantTaskSections oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contexts != widget.contexts ||
        oldWidget.activeContext.id != widget.activeContext.id) {
      _data = _load();
    }
    if (oldWidget.page.location != widget.page.location) _expandedKey = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _refresh();
  }

  @override
  void dispose() {
    _categoryScroll.dispose();
    _wakeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _setDisposition(
    AssistantTask item,
    String status, {
    int? minutes,
  }) async {
    final service = widget.overview;
    if (service is! AssistantTaskStateServices || _opening || item.stale) {
      return;
    }
    setState(() => _opening = true);
    try {
      await (service as AssistantTaskStateServices).setAssistantTaskState(
        contextId: item.context.id,
        kind: item.task.kind,
        route: item.task.route,
        status: status,
        snoozeMinutes: minutes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'archived'
                ? item.task.kind == 'calendar_conflict'
                      ? 'Överlappningen är avfärdad i din lista. Aktiviteterna är oförändrade.'
                      : 'Arkiverad i din lista. Aktiviteten är oförändrad.'
                : status == 'snoozed'
                ? 'Uppgiften har skjutits upp i din lista.'
                : 'Uppgiften är återställd.',
          ),
          action: status == 'active'
              ? null
              : SnackBarAction(
                  label: 'Ångra',
                  onPressed: () => _setDisposition(item, 'active'),
                ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Valet kunde inte sparas. Uppdatera och försök igen.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
          _data = _load();
        });
      }
    }
  }

  Future<void> _open(AssistantTask task) async {
    setState(() => _opening = true);
    try {
      await widget.onOpen(task);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aktiviteten kunde inte öppnas. Försök igen.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
          _data = _load();
        });
      }
    }
  }

  Future<void> _dismissWelcome(AssistantTaskPreferences preferences) async {
    final service = widget.overview;
    if (service is! AssistantTaskPreferencesServices || _welcomeDismissed) {
      return;
    }
    final preferencesService = service as AssistantTaskPreferencesServices;
    setState(() => _welcomeDismissed = true);
    try {
      final saved = await preferencesService.saveAssistantTaskPreferences(
        preferences.hiddenKinds,
        preferences.revision,
        currentTeamOnly: preferences.currentTeamOnly,
        welcomeMessageVisible: false,
      );
      if (!saved.welcomeMessageVisible) return;
      throw StateError('welcome preference was not saved');
    } catch (_) {
      if (!mounted) return;
      setState(() => _welcomeDismissed = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Välkomstmeddelandet kunde inte döljas. Försök igen.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FutureBuilder<AssistantTaskSnapshot>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return const Text(
              'Uppgifterna kunde inte hämtas. Försök uppdatera.',
            );
          }
          final data = snapshot.requireData;
          final bucketTasks = data.tasks
              .where((t) => t.task.assistantStatus == _bucket)
              .toList();
          final categories = <String, String>{
            'all': 'Alla',
            'important': 'Viktigt',
            'preparation': 'Förberedelser',
            'matches': 'Matcher',
            'training': 'Träningar',
            'other': 'Övrigt',
          };
          final counts = {
            for (final key in categories.keys)
              key: bucketTasks.where((t) => t.inCategory(key)).length,
          };
          final selectedCategory = (counts[_category] ?? 0) > 0
              ? _category
              : 'all';
          final visible = bucketTasks
              .where((t) => t.inCategory(selectedCategory))
              .toList();
          final here = visible
              .where(
                (task) =>
                    _bucket == 'active' &&
                    !widget.page.isHome &&
                    ((task.context.clubId == widget.activeContext.clubId &&
                            task.context.teamId ==
                                widget.activeContext.teamId) ||
                        (task.overlappingContext?.clubId ==
                                widget.activeContext.clubId &&
                            task.overlappingContext?.teamId ==
                                widget.activeContext.teamId)) &&
                    widget.page.isRelevant(task),
              )
              .toList();
          final hereKeys = here.map((task) => task.key).toSet();
          final remaining = visible
              .where((task) => !hereKeys.contains(task.key))
              .toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (data.preferences.welcomeMessageVisible &&
                  !_welcomeDismissed) ...[
                Container(
                  key: const Key('assistant-welcome-message'),
                  padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hej! Jag är din assistent.',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Jag hjälper dig att hitta det som behöver göras och komma vidare.',
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const Key('assistant-dismiss-welcome'),
                        tooltip: 'Dölj välkomstmeddelandet',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _dismissWelcome(data.preferences),
                        icon: const Icon(Icons.close, size: 20),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  for (final entry in const {
                    'active': 'Aktuellt',
                    'snoozed': 'Uppskjutet',
                    'archived': 'Arkiverat',
                  }.entries) ...[
                    IconButton.filledTonal(
                      key: ValueKey('assistant-filter-${entry.key}'),
                      tooltip:
                          '${entry.value} (${data.tasks.where((t) => t.task.assistantStatus == entry.key).length})',
                      style: IconButton.styleFrom(
                        fixedSize: const Size(52, 44),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: Icon(switch (entry.key) {
                        'snoozed' => Icons.snooze_outlined,
                        'archived' => Icons.archive_outlined,
                        _ => Icons.inbox_outlined,
                      }),
                      isSelected: _bucket == entry.key,
                      onPressed: () => setState(() {
                        _bucket = entry.key;
                        _category = 'all';
                        _expandedKey = null;
                      }),
                    ),
                    if (entry.key != 'archived') const SizedBox(width: 10),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              if (bucketTasks.isNotEmpty) ...[
                Scrollbar(
                  controller: _categoryScroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _categoryScroll,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        for (final category in categories.entries)
                          if (category.key == 'all' ||
                              counts[category.key]! > 0)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                key: ValueKey(
                                  'assistant-category-${category.key}',
                                ),
                                label: Text(
                                  '${category.value} (${counts[category.key]})',
                                ),
                                selected: selectedCategory == category.key,
                                onSelected: (_) => setState(() {
                                  _category = category.key;
                                  _expandedKey = null;
                                }),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (data.currentTeamOnly) ...[
                Text(
                  widget.activeContext.teamId == null
                      ? 'Välj ett lag i appen för att se dess uppgifter.'
                      : 'Visar: ${widget.activeContext.clubName} · ${widget.activeContext.teamName}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
              ],
              if (selectedCategory == 'important') ...[
                const Text(
                  'Kalenderkrockar och uppgifter inför aktiviteter som börjar inom ett dygn.',
                ),
                const SizedBox(height: 16),
              ],
              if (data.settingsFailed)
                const Text(
                  'Dina visningsinställningar kunde inte hämtas. Försök uppdatera.',
                ),
              if (data.personalFailed)
                const Text(
                  'Dina personliga kalenderkrockar kunde inte kontrolleras. Försök uppdatera.',
                ),
              if (data.failedContexts.isNotEmpty)
                Text(
                  'Kunde inte hämta aktuella uppgifter för: '
                  '${data.failedContexts.map((c) => '${c.clubName} · ${c.teamName}').join(', ')}. '
                  'Överblicken är ofullständig. Försök uppdatera.',
                  key: const Key('assistant-task-error'),
                ),
              if (here.isNotEmpty) ...[
                Text(
                  'Här och nu',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  '${widget.page.label} · ${widget.activeContext.teamName ?? widget.activeContext.clubName}',
                ),
                const SizedBox(height: 12),
                ..._cards(context, here),
                const SizedBox(height: 20),
              ],
              if (_bucket != 'active' && (remaining.isNotEmpty || here.isEmpty))
                Text(
                  _bucket == 'snoozed'
                      ? 'Uppskjutna uppgifter'
                      : 'Arkiverade uppgifter',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              if (_bucket != 'active') const SizedBox(height: 12),
              if (_bucket != 'active')
                const Text(
                  'Visar uppgifter som fortfarande är relevanta och som du har behörighet att se.',
                ),
              if (remaining.isEmpty && here.isEmpty)
                Text(
                  data.settingsFailed
                      ? 'Uppgifterna visas när dina inställningar har hämtats.'
                      : data.failedContexts.isNotEmpty || data.personalFailed
                      ? 'Alla lag kunde inte kontrolleras.'
                      : data.filtersActive
                      ? 'Inga fler uppgifter att visa med dina inställningar.'
                      : here.isNotEmpty
                      ? 'Övriga uppgifter är klara.'
                      : 'Inga aktuella uppgifter att visa.',
                ),
              ..._cards(context, remaining),
            ],
          );
        },
      ),
    ],
  );

  Iterable<Widget> _cards(
    BuildContext context,
    List<AssistantTask> tasks,
  ) sync* {
    final groups = <String, List<AssistantTask>>{};
    for (final task in tasks) {
      final groupKey = '${task.context.id}:${task.eventId}';
      (groups[groupKey] ??= []).add(task);
    }
    for (final group in groups.values) {
      yield group.length == 1
          ? _card(context, group.single)
          : _groupCard(context, group);
    }
  }

  Widget _groupCard(BuildContext context, List<AssistantTask> items) {
    final item = items.first;
    final date = item.startsAt?.toLocal();
    final material = MaterialLocalizations.of(context);
    return Card(
      key: ValueKey('assistant-task-group-${item.context.id}:${item.eventId}'),
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            key: ValueKey(
              'assistant-group-header-${item.context.id}:${item.eventId}',
            ),
            contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            title: Text(
              [
                item.context.clubName,
                if (item.context.teamName != null) item.context.teamName!,
              ].join(' · '),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                Text(
                  item.eventTitle ?? 'Aktivitet',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (date != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${material.formatShortDate(date)} ${material.formatTimeOfDay(TimeOfDay.fromDateTime(date))}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  '${items.length} saker att hantera',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (var index = 0; index < items.length; index++) ...[
            _card(context, items[index], grouped: true),
            if (index < items.length - 1)
              const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        ],
      ),
    );
  }

  Widget _card(
    BuildContext context,
    AssistantTask item, {
    bool grouped = false,
  }) {
    final date = item.startsAt?.toLocal();
    final observed = item.generatedAt.toLocal();
    final material = MaterialLocalizations.of(context);
    final expanded = _expandedKey == item.key;
    final canOrganize =
        widget.overview is AssistantTaskStateServices &&
        !item.stale &&
        !_opening;
    final title =
        item.task.kind == 'missing_callups' ||
            item.isMatchFollowup ||
            item.overlappingEvent != null
        ? item.task.title
        : '${item.task.title} (${item.task.count})';
    return Card(
      margin: grouped ? EdgeInsets.zero : const EdgeInsets.only(bottom: 16),
      elevation: 0,
      color: grouped ? Colors.transparent : null,
      shape: grouped
          ? const RoundedRectangleBorder()
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
      key: ValueKey('assistant-task-${item.key}'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            key: ValueKey('assistant-expand-${item.key}'),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            title: Padding(
              padding: EdgeInsets.only(bottom: grouped ? 0 : 8),
              child: Semantics(
                header: true,
                child: Text(
                  grouped
                      ? title
                      : [
                              item.context.clubName,
                              if (item.context.teamName != null)
                                item.context.teamName!,
                            ].join(' · ') +
                            (item.isPersonalConflict
                                ? '\n↔ ${item.eventContextLabel(item.overlappingEvent!.id)}'
                                : ''),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: grouped ? FontWeight.w600 : FontWeight.bold,
                    color: grouped
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
            subtitle: grouped
                ? item.overlappingEvent == null
                      ? null
                      : Text(
                          '↔ ${item.overlappingEvent!.title}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.eventTitle ?? 'Aktivitet',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.overlappingEvent != null)
                        Text(
                          '↔ ${item.overlappingEvent!.title}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (date != null) const SizedBox(height: 6),
                      if (date != null)
                        Text(
                          '${material.formatShortDate(date)} ${material.formatTimeOfDay(TimeOfDay.fromDateTime(date))}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                    ],
                  ),
            trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
            onTap: () =>
                setState(() => _expandedKey = expanded ? null : item.key),
          ),
          if (item.stale)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('Sparade uppgifter – uppdatera före åtgärd.'),
            ),
          if (item.task.assistantStatus == 'snoozed' &&
              item.task.snoozedUntil != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Uppskjutet till ${material.formatShortDate(item.task.snoozedUntil!.toLocal())} '
                '${material.formatTimeOfDay(TimeOfDay.fromDateTime(item.task.snoozedUntil!.toLocal()))}',
              ),
            ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.task.kind == 'unfinished_preparation' &&
                      widget.preparation != null)
                    AssistantPreparationChecklist(
                      key: ValueKey('assistant-checklist-${item.key}'),
                      eventId: item.eventId,
                      services: widget.preparation!,
                      loadEvent: widget.loadEvent,
                      allowEdit:
                          !item.stale &&
                          !_opening &&
                          item.context.can('event.logistics'),
                      onChanged: _refresh,
                    ),
                  const Text('Varför visas detta?'),
                  Text(item.explanation),
                  if (item.overlappingEvent == null &&
                      item.startsAt != null &&
                      item.endsAt != null)
                    Text(_eventInterval(context, item.startsAt!, item.endsAt!)),
                  if (item.overlappingEvent != null) ...[
                    for (final event in [
                      item.eventDetails,
                      item.overlappingEvent,
                    ].whereType<EventDetails>())
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.title,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(item.eventContextLabel(event.id)),
                            if (item.isPersonalConflict)
                              Text(
                                (event.id == item.eventId
                                            ? item.response
                                            : item.overlappingResponse) ==
                                        'accepted'
                                    ? 'Ditt svar: Kommer'
                                    : 'Ditt svar: Obesvarat',
                              ),
                            Text(
                              _eventInterval(
                                context,
                                event.startsAt,
                                event.endsAt,
                              ),
                            ),
                            Text(
                              [event.locationName, event.locationPitch]
                                      .whereType<String>()
                                      .where((s) => s.isNotEmpty)
                                      .join(' · ')
                                      .isEmpty
                                  ? 'Plats saknas'
                                  : [event.locationName, event.locationPitch]
                                        .whereType<String>()
                                        .where((s) => s.isNotEmpty)
                                        .join(' · '),
                            ),
                          ],
                        ),
                      ),
                    const Text(
                      'Avsiktlig överlappning avfärdar bara detta aktivitetspar i din egen lista. Du kan återställa det under Arkiverat.',
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Källa: lagets kalender, kallelser, förberedelselistor och uppföljning. '
                    'Hämtat ${material.formatShortDate(observed)} '
                    '${material.formatTimeOfDay(TimeOfDay.fromDateTime(observed))}.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: item.actionLabel,
                    child: FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: const Size(0, 44),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: item.stale || _opening
                          ? null
                          : () {
                              if (item.task.kind == 'unfinished_preparation' &&
                                  widget.preparation != null &&
                                  !expanded) {
                                setState(() => _expandedKey = item.key);
                              } else {
                                _open(item);
                              }
                            },
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          item.isPersonalConflict
                              ? 'Hantera'
                              : item.overlappingEvent != null
                              ? 'Ändra tid'
                              : 'Åtgärda',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ),
                if (item.task.assistantStatus == 'active') ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: PopupMenuButton<int>(
                      tooltip: 'Skjut upp',
                      enabled: canOrganize,
                      child: SizedBox(
                        height: 44,
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Skjut upp',
                              style: TextStyle(
                                fontSize: 12,
                                color: canOrganize
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).disabledColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                      onSelected: (minutes) =>
                          _setDisposition(item, 'snoozed', minutes: minutes),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 60, child: Text('Om en timme')),
                        PopupMenuItem(value: 1440, child: Text('Om ett dygn')),
                        PopupMenuItem(value: 10080, child: Text('Om en vecka')),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Tooltip(
                      message: item.overlappingEvent != null
                          ? 'Avsiktlig överlappning'
                          : 'Arkivera',
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: const Size(0, 44),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: canOrganize
                            ? () => _setDisposition(item, 'archived')
                            : null,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            item.overlappingEvent != null
                                ? 'Avsiktlig\növerlappning'
                                : 'Arkivera',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton(
                      onPressed: canOrganize
                          ? () => _setDisposition(item, 'active')
                          : null,
                      child: const Text('Återställ'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _eventInterval(BuildContext context, DateTime start, DateTime end) {
    final material = MaterialLocalizations.of(context);
    String stamp(DateTime value) =>
        '${material.formatShortDate(value.toLocal())} '
        '${material.formatTimeOfDay(TimeOfDay.fromDateTime(value.toLocal()))}';
    return '${stamp(start)}–${stamp(end)}';
  }
}
