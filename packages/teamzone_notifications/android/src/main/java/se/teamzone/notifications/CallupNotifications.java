package se.teamzone.notifications;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.RemoteInput;
import android.content.Context;
import android.content.Intent;
import android.graphics.drawable.Icon;
import android.os.Build;
import android.os.Bundle;

/**
 * Builds TeamZone's notifications. Lock-screen text is what the server sent
 * (type + activity, never names or free text). A callup that can be answered
 * gets "Kommer" (answered here, after unlock) and "Kan inte…" (opens the
 * event, since a decline needs a reason); a message one can reply to gets
 * "Svara" with a text field (sent after unlock).
 */
final class CallupNotifications {
  static final String CHANNEL_ID = "teamzone_push";
  static final String EXTRA_ROUTE = "se.teamzone.notifications.ROUTE";
  static final String KIND_CALLUP = "callup";
  static final String KIND_REPLY = "reply";

  // Keys of the action broadcast; everything the receiver needs to send and
  // to replace the notification afterwards.
  static final String KEY_KIND = "kind";
  static final String KEY_ID = "id";
  static final String KEY_TITLE = "title";
  static final String KEY_BODY = "body";
  static final String KEY_ROUTE = "route";
  static final String KEY_TOKEN = "token";
  static final String KEY_IDEMPOTENCY = "idempotencyKey";
  static final String KEY_ENDPOINT = "endpoint";
  static final String KEY_API_KEY = "apiKey";
  static final String KEY_SENT = "sentTitle";
  static final String KEY_GONE = "goneTitle";
  static final String KEY_FAILED = "failedTitle";
  static final String KEY_LOCKED = "lockedTitle";
  static final String KEY_REPLY = "reply";

  private CallupNotifications() {}

  static void createChannel(Context context, String name, String description) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
    NotificationChannel channel =
        new NotificationChannel(CHANNEL_ID, name, NotificationManager.IMPORTANCE_HIGH);
    channel.setDescription(description);
    manager(context).createNotificationChannel(channel);
  }

  /** A notification that opens [route] when tapped. */
  static void showPlain(Context context, int id, String title, String body, String route) {
    showPlain(context, id, title, body, route, 0);
  }

  /** As above; with [timeoutMs] > 0 it removes itself after that long. */
  static void showPlain(Context context, int id, String title, String body, String route,
      long timeoutMs) {
    Notification.Builder builder = base(context, id, title, body, route);
    if (timeoutMs > 0 && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      builder.setTimeoutAfter(timeoutMs);
    }
    manager(context).notify(id, builder.build());
  }

  static void showCallup(Context context, Bundle values, String acceptLabel, String declineLabel,
      String declineRoute) {
    int id = values.getInt(KEY_ID);
    values.putString(KEY_KIND, KIND_CALLUP);
    Notification.Builder builder = base(context, id, values.getString(KEY_TITLE),
        values.getString(KEY_BODY), values.getString(KEY_ROUTE));
    Notification.Action.Builder accept = new Notification.Action.Builder(
        Icon.createWithResource(context, smallIcon(context)), acceptLabel,
        actionIntent(context, id * 4 + 1, values, false));
    requireUnlock(accept);
    Notification.Action.Builder decline = new Notification.Action.Builder(
        Icon.createWithResource(context, smallIcon(context)), declineLabel,
        openIntent(context, id * 4 + 2, declineRoute));
    builder.addAction(accept.build()).addAction(decline.build());
    manager(context).notify(id, builder.build());
  }

  static void showMessage(Context context, Bundle values, String replyLabel, String replyHint) {
    int id = values.getInt(KEY_ID);
    values.putString(KEY_KIND, KIND_REPLY);
    Notification.Builder builder = base(context, id, values.getString(KEY_TITLE),
        values.getString(KEY_BODY), values.getString(KEY_ROUTE));
    Notification.Action.Builder reply = new Notification.Action.Builder(
        Icon.createWithResource(context, smallIcon(context)), replyLabel,
        actionIntent(context, id * 4 + 3, values, true))
        .addRemoteInput(new RemoteInput.Builder(KEY_REPLY).setLabel(replyHint).build());
    requireUnlock(reply);
    builder.addAction(reply.build());
    manager(context).notify(id, builder.build());
  }

  static Notification.Builder base(Context context, int id, String title, String body,
      String route) {
    Notification.Builder builder = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
        ? new Notification.Builder(context, CHANNEL_ID)
        : new Notification.Builder(context);
    builder
        .setSmallIcon(smallIcon(context))
        .setContentTitle(title)
        .setContentText(body)
        .setAutoCancel(true)
        .setOnlyAlertOnce(true)
        .setContentIntent(openIntent(context, id * 4, route));
    int color = context.getResources()
        .getIdentifier("notification_color", "color", context.getPackageName());
    if (color != 0) builder.setColor(context.getColor(color));
    return builder;
  }

  /** Android asks for unlock before the action runs (decided 2026-10-13). */
  private static void requireUnlock(Notification.Action.Builder action) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) action.setAuthenticationRequired(true);
  }

  /** The broadcast to [PushActionReceiver]; mutable when it carries typed text. */
  private static PendingIntent actionIntent(Context context, int requestCode, Bundle values,
      boolean takesText) {
    Intent intent = new Intent(context, PushActionReceiver.class).putExtras(values);
    int flags = PendingIntent.FLAG_UPDATE_CURRENT;
    flags |= takesText && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
        ? PendingIntent.FLAG_MUTABLE
        : PendingIntent.FLAG_IMMUTABLE;
    return PendingIntent.getBroadcast(context, requestCode, intent, flags);
  }

  /** Opens the app at [route] (the app checks it against its own routes). */
  static PendingIntent openIntent(Context context, int requestCode, String route) {
    Intent intent = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
    if (intent == null) intent = new Intent();
    intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
    intent.putExtra(EXTRA_ROUTE, route);
    return PendingIntent.getActivity(context, requestCode, intent,
        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
  }

  static int smallIcon(Context context) {
    int icon = context.getResources()
        .getIdentifier("ic_stat_teamzone", "drawable", context.getPackageName());
    return icon != 0 ? icon : context.getApplicationInfo().icon;
  }

  static NotificationManager manager(Context context) {
    return (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
  }
}
