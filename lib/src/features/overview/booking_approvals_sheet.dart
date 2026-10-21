import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:teamzone_app/src/core/observability/app_errors.dart';
import 'overview_models.dart';
import 'overview_services.dart';

/// Bokningshanterare in the app: approve or decline the bookings that wait
/// in an organisation. Webtools stays one tap away for the rest.
Future<void> showBookingApprovalsSheet(
  BuildContext context, {
  required BookingDecisionServices services,
  required String organizationId,
  required String organizationName,
  required String webtoolsUrl,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => BookingApprovalsSheet(
    services: services,
    organizationId: organizationId,
    organizationName: organizationName,
    webtoolsUrl: webtoolsUrl,
  ),
);

class BookingApprovalsSheet extends StatefulWidget {
  const BookingApprovalsSheet({
    super.key,
    required this.services,
    required this.organizationId,
    required this.organizationName,
    required this.webtoolsUrl,
  });
  final BookingDecisionServices services;
  final String organizationId, organizationName, webtoolsUrl;

  @override
  State<BookingApprovalsSheet> createState() => _BookingApprovalsSheetState();
}

class _BookingApprovalsSheetState extends State<BookingApprovalsSheet> {
  late Future<List<PendingBooking>> _pending = _load();
  String? _deciding, _error, _notice;

  /// Waiting bookings per series, so a series says how many it decides.
  final _seriesCounts = <String, int>{};

  // A series or a group is one request: only its first booking is shown.
  Future<List<PendingBooking>> _load() async {
    try {
      final all = await widget.services.listPendingBookings(
        widget.organizationId,
      );
      final seen = <String>{};
      _seriesCounts.clear();
      for (final booking in all) {
        if (booking.seriesId case final id?) {
          _seriesCounts[id] = (_seriesCounts[id] ?? 0) + 1;
        }
      }
      return [
        for (final booking in all)
          if (seen.add(booking.seriesId ?? booking.groupId ?? booking.id))
            booking,
      ];
    } catch (error) {
      AppErrors.caught('booking_approvals_sheet.load', error);
      rethrow;
    }
  }

  Future<void> _decide(PendingBooking booking, bool approve) async {
    setState(() {
      _deciding = booking.id;
      _error = null;
      _notice = null;
    });
    try {
      await widget.services.decideBooking(booking, approve: approve);
      if (!mounted) return;
      setState(() {
        _deciding = null;
        _notice = approve ? 'Godkänd.' : 'Nekad.';
        _pending = _load();
      });
    } catch (error) {
      AppErrors.caught('booking_approvals_sheet.decide', error);
      if (!mounted) return;
      final handled = error.toString().contains('not_pending');
      setState(() {
        _deciding = null;
        _error = handled
            ? 'Bokningen är redan hanterad.'
            : 'Beslutet kunde inte sparas. Försök igen.';
        if (handled) _pending = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<PendingBooking>>(
      future: _pending,
      builder: (context, snapshot) {
        final pending = snapshot.data ?? const <PendingBooking>[];
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Bokningar att godkänna', style: theme.textTheme.titleLarge),
              if (widget.organizationName.isNotEmpty)
                Text(widget.organizationName, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Flexible(
                child: snapshot.connectionState != ConnectionState.done
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : snapshot.hasError
                    ? const Text('Bokningarna kunde inte hämtas. Försök igen.')
                    : pending.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('Inget väntar på godkännande just nu.'),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final booking in pending)
                            _request(context, booking),
                        ],
                      ),
              ),
              if (_error ?? _notice case final message?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    message,
                    style: _error == null
                        ? theme.textTheme.bodySmall
                        : TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: 8),
              TextButton.icon(
                key: const ValueKey('booking-approvals-webtools'),
                onPressed: () => launchUrl(
                  Uri.parse(widget.webtoolsUrl),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Öppna Bokningshanteraren'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _request(BuildContext context, PendingBooking booking) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    String time(DateTime value) =>
        TimeOfDay.fromDateTime(value.toLocal()).format(context);
    final series = booking.seriesId != null;
    final group = !series && booking.groupId != null;
    final busy = _deciding != null;
    return Card(
      key: ValueKey('booking-approval-${booking.id}'),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              group && booking.groupResources.isNotEmpty
                  ? booking.groupResources.join(', ')
                  : booking.resourceName,
              style: theme.textTheme.titleSmall,
            ),
            Text(
              '${localizations.formatMediumDate(booking.startsAt.toLocal())} '
              '${time(booking.startsAt)}–${time(booking.endsAt)}'
              '${series ? ' · återkommande, ${_seriesCounts[booking.seriesId] ?? 1} tillfällen' : ''}',
            ),
            Text(
              [
                ?booking.teamName,
                ?(booking.eventTitle ?? booking.title),
                if (booking.bookedByName case final name?) 'bokad av $name',
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            if (booking.notes case final notes? when notes.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(notes, style: theme.textTheme.bodySmall),
              ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                OutlinedButton(
                  key: ValueKey('booking-decline-${booking.id}'),
                  onPressed: busy ? null : () => _decide(booking, false),
                  child: Text(
                    series
                        ? 'Neka serien'
                        : group
                        ? 'Neka alla'
                        : 'Neka',
                  ),
                ),
                FilledButton(
                  key: ValueKey('booking-approve-${booking.id}'),
                  onPressed: busy ? null : () => _decide(booking, true),
                  child: Text(
                    series
                        ? 'Godkänn serien'
                        : group
                        ? 'Godkänn alla'
                        : 'Godkänn',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
