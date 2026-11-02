package se.teamzone.notifications;

import android.app.KeyguardManager;
import android.app.RemoteInput;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.Bundle;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import org.json.JSONObject;

/**
 * "Kommer" on a callup, "Svara" on a message and 1–10 on the effort
 * question: sends the token (and the reply text or the answer) to
 * push-callup-response, push-message-reply or push-effort-response, then
 * replaces the notification with the outcome. Neither the token nor the text
 * is logged, and the text is never shown in the notification.
 */
public final class PushActionReceiver extends BroadcastReceiver {
  /** A confirmation stays this long, then removes itself; failures stay. */
  private static final long CONFIRMATION_MS = 5000;

  @Override
  public void onReceive(Context context, Intent intent) {
    final Bundle values = intent.getExtras();
    if (values == null) return;
    final String reply = replyText(intent);
    final Context app = context.getApplicationContext();
    final PendingResult pending = goAsync();
    new Thread(() -> {
      try {
        String outcome = outcome(app, values, reply);
        // The effort question's confirmation names the answer.
        String title = values.getString(outcome, "")
            .replace("{rating}", String.valueOf(values.getInt(CallupNotifications.KEY_RATING)));
        CallupNotifications.showPlain(app, values.getInt(CallupNotifications.KEY_ID),
            title, values.getString(CallupNotifications.KEY_BODY),
            values.getString(CallupNotifications.KEY_ROUTE),
            CallupNotifications.KEY_SENT.equals(outcome) ? CONFIRMATION_MS : 0);
      } finally {
        pending.finish();
      }
    }).start();
  }

  private static String replyText(Intent intent) {
    Bundle input = RemoteInput.getResultsFromIntent(intent);
    if (input == null) return null;
    CharSequence text = input.getCharSequence(CallupNotifications.KEY_REPLY);
    return text == null ? null : text.toString();
  }

  /** The key of the outcome's title: sent, gone, failed or locked. */
  private static String outcome(Context context, Bundle values, String reply) {
    // Android 12+ requires unlock before this runs; older versions answer
    // only on an unlocked phone.
    // The effort question's buttons live in the notification's own layout,
    // which cannot ask for unlock: it answers only on an unlocked phone.
    String kind = values.getString(CallupNotifications.KEY_KIND);
    boolean isEffort = CallupNotifications.KIND_EFFORT.equals(kind);
    KeyguardManager keyguard = (KeyguardManager) context.getSystemService(Context.KEYGUARD_SERVICE);
    if ((isEffort || Build.VERSION.SDK_INT < Build.VERSION_CODES.S) && keyguard != null
        && keyguard.isDeviceLocked()) {
      return CallupNotifications.KEY_LOCKED;
    }
    boolean isReply = CallupNotifications.KIND_REPLY.equals(kind);
    if (isReply && (reply == null || reply.trim().isEmpty())) {
      return CallupNotifications.KEY_FAILED;
    }
    int status = send(values, isReply ? reply : null,
        isEffort ? values.getInt(CallupNotifications.KEY_RATING) : 0);
    if (status == 200) return CallupNotifications.KEY_SENT;
    if (status == 410) return CallupNotifications.KEY_GONE;
    return CallupNotifications.KEY_FAILED;
  }

  /** The HTTP status, or 0 when the request did not complete. */
  private static int send(Bundle values, String reply, int rating) {
    HttpURLConnection connection = null;
    try {
      JSONObject body = new JSONObject()
          .put("token", values.getString(CallupNotifications.KEY_TOKEN))
          .put("idempotency_key", values.getString(CallupNotifications.KEY_IDEMPOTENCY));
      if (reply != null) body.put("body", reply);
      if (rating > 0) body.put("rating", rating);
      connection = (HttpURLConnection) new URL(
          values.getString(CallupNotifications.KEY_ENDPOINT)).openConnection();
      connection.setRequestMethod("POST");
      connection.setConnectTimeout(15000);
      connection.setReadTimeout(15000);
      connection.setDoOutput(true);
      connection.setRequestProperty("content-type", "application/json");
      connection.setRequestProperty("apikey", values.getString(CallupNotifications.KEY_API_KEY));
      try (OutputStream out = connection.getOutputStream()) {
        out.write(body.toString().getBytes(StandardCharsets.UTF_8));
      }
      return connection.getResponseCode();
    } catch (Exception error) {
      return 0;
    } finally {
      if (connection != null) connection.disconnect();
    }
  }
}
