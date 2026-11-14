import 'package:flutter/material.dart';
import 'package:teamzone_app/src/core/localization/support_strings.dart';
import 'package:teamzone_app/src/core/observability/app_errors.dart';
import 'package:teamzone_app/src/features/support/support_admin_services.dart';
import 'package:teamzone_app/src/features/support/support_clubs_tab.dart'
    show supportDate;

/// Supportadmins on the support admin page: who is a support administrator,
/// adding one by sign-in address and removing one, each with a reason.
class SupportAdminsTab extends StatefulWidget {
  const SupportAdminsTab({
    super.key,
    required this.services,
    this.onSelfRemoved,
  });
  final SupportAdminServices services;

  /// Called after removing one's own right (the page then closes for this
  /// account).
  final VoidCallback? onSelfRemoved;

  @override
  State<SupportAdminsTab> createState() => _SupportAdminsTabState();
}

class _SupportAdminsTabState extends State<SupportAdminsTab> {
  late Future<List<SupportAdmin>> _admins = _load();
  bool _saving = false;

  Future<List<SupportAdmin>> _load() =>
      widget.services.listSupportAdmins().timeout(const Duration(seconds: 15));

  void _reload() => setState(() => _admins = _load());

  Future<({String email, String reason})?> _askAdd() {
    final strings = SupportStrings.of(context);
    final formKey = GlobalKey<FormState>();
    var email = '';
    var reason = '';
    return showDialog<({String email, String reason})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.addAdmin),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey('support-admin-email'),
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: strings.emailLabel,
                  helperText: strings.emailHint,
                ),
                onChanged: (value) => email = value,
                validator: (value) => (value ?? '').contains('@')
                    ? null
                    : strings.refusal('account_not_found'),
              ),
              const SizedBox(height: 12),
              _reasonField(strings, (value) => reason = value),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(strings.cancel),
          ),
          FilledButton(
            key: const ValueKey('support-admin-add-confirm'),
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(dialogContext, (email: email, reason: reason));
            },
            child: Text(strings.add),
          ),
        ],
      ),
    );
  }

  Future<String?> _askRemove(SupportAdmin admin) {
    final strings = SupportStrings.of(context);
    final formKey = GlobalKey<FormState>();
    var reason = '';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.removeAdminTitle),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.removeAdminBody(admin.name, admin.isSelf)),
              const SizedBox(height: 12),
              _reasonField(strings, (value) => reason = value),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(strings.cancel),
          ),
          FilledButton(
            key: const ValueKey('support-admin-remove-confirm'),
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(dialogContext, reason);
            },
            child: Text(strings.removeAdmin),
          ),
        ],
      ),
    );
  }

  Widget _reasonField(SupportStrings strings, ValueChanged<String> onChanged) =>
      TextFormField(
        key: const ValueKey('support-admin-reason'),
        minLines: 2,
        maxLines: 4,
        maxLength: 500,
        decoration: InputDecoration(labelText: strings.reasonLabel),
        onChanged: onChanged,
        validator: (value) =>
            (value?.trim().length ?? 0) < 5 ? strings.reasonTooShort : null,
      );

  Future<void> _run(Future<void> Function() change, String done) async {
    final strings = SupportStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await change();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      if (mounted) _reload();
    } catch (error) {
      final code = supportAdminRefusal(error);
      if (code == null) AppErrors.caught('support_admins_tab.change', error);
      messenger.showSnackBar(SnackBar(content: Text(strings.refusal(code))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _add() async {
    final strings = SupportStrings.of(context);
    final input = await _askAdd();
    if (input == null || !mounted) return;
    await _run(
      () => widget.services.grantSupportAdmin(
        email: input.email,
        reason: input.reason,
      ),
      strings.added,
    );
  }

  Future<void> _remove(SupportAdmin admin) async {
    final strings = SupportStrings.of(context);
    final reason = await _askRemove(admin);
    if (reason == null || !mounted) return;
    var removed = false;
    await _run(() async {
      await widget.services.revokeSupportAdmin(
        profileId: admin.profileId,
        reason: reason,
      );
      removed = true;
    }, strings.removed);
    if (removed && admin.isSelf) widget.onSelfRemoved?.call();
  }

  @override
  Widget build(BuildContext context) {
    final strings = SupportStrings.of(context);
    final theme = Theme.of(context);
    return FutureBuilder<List<SupportAdmin>>(
      future: _admins,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          AppErrors.caught('support_admins_tab.load', snapshot.error!);
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(strings.adminsFailed),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _reload, child: Text(strings.retry)),
              ],
            ),
          );
        }
        final admins = snapshot.data ?? const <SupportAdmin>[];
        final active = admins.where((admin) => admin.active).toList();
        final earlier = admins.where((admin) => !admin.active).toList();
        Widget row(SupportAdmin admin) => Card(
          key: ValueKey('support-admin-${admin.profileId}'),
          child: ListTile(
            leading: Icon(
              admin.active ? Icons.support_agent : Icons.person_off_outlined,
            ),
            title: Text(
              admin.isSelf ? '${admin.name} (${strings.you})' : admin.name,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (admin.email.isNotEmpty) Text(admin.email),
                Text(
                  admin.active
                      ? strings.sinceDate(supportDate(admin.createdAt))
                      : strings.revokedOn(
                          supportDate(admin.revokedAt ?? admin.createdAt),
                        ),
                ),
                if (admin.active && admin.clubCount > 0)
                  Text(
                    strings.clubRoles(admin.clubCount),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
              ],
            ),
            trailing: admin.active
                ? TextButton(
                    key: ValueKey('support-admin-remove-${admin.profileId}'),
                    onPressed: _saving ? null : () => _remove(admin),
                    child: Text(strings.removeAdmin),
                  )
                : null,
          ),
        );
        return ListView(
          key: const ValueKey('support-admins'),
          padding: const EdgeInsets.all(16),
          children: [
            Text(strings.adminsIntro),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const ValueKey('support-admin-add'),
                onPressed: _saving ? null : _add,
                icon: const Icon(Icons.person_add_alt),
                label: Text(strings.addAdmin),
              ),
            ),
            const SizedBox(height: 12),
            for (final admin in active) row(admin),
            if (earlier.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 4),
                child: Text(strings.earlier, style: theme.textTheme.titleSmall),
              ),
              for (final admin in earlier) row(admin),
            ],
          ],
        );
      },
    );
  }
}
