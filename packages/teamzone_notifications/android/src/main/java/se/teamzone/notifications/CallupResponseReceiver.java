package se.teamzone.notifications;

import android.app.KeyguardManager;
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
 * "Kommer" from a callup notification: sends the single-use response token
 * to push-callup-response and replaces the notification with the outcome.
 * Neither the token nor the reply is logged.
 */
public final class CallupResponseReceiver extends BroadcastReceiver {
  @Override
  public void onReceive(Context context, Intent intent) {
    final Bundle values = intent.getExtras();
    if (values == null) return;
    final Context app = context.getApplicationContext();
    final PendingResult pending = goAsync();
    new Thread(() -> {
      try {
        String title = outcomeTitle(app, values);
        CallupNotifications.showPlain(app, values.getInt(CallupNotifications.KEY_ID), title,
            values.getString(CallupNotifications.KEY_BODY),
            values.getString(CallupNotifications.KEY_ROUTE));
      } finally {
        pending.finish();
      }
    }).start();
  }

  private static String outcomeTitle(Context context, Bundle values) {
    // Android 12+ requires unlock before this runs; older versions answer
    // only on an unlocked phone.
    KeyguardManager keyguard = (KeyguardManager) context.getSystemService(Context.KEYGUARD_SERVICE);
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S && keyguard != null
        && keyguard.isDeviceLocked()) {
      return values.getString(CallupNotifications.KEY_LOCKED);
    }
    int status = send(values);
    if (status == 200) return values.getString(CallupNotifications.KEY_SENT);
    if (status == 410) return values.getString(CallupNotifications.KEY_GONE);
    return values.getString(CallupNotifications.KEY_FAILED);
  }

  /** The HTTP status, or 0 when the request did not complete. */
  private static int send(Bundle values) {
    HttpURLConnection connection = null;
    try {
      JSONObject body = new JSONObject()
          .put("token", values.getString(CallupNotifications.KEY_TOKEN))
          .put("idempotency_key", values.getString(CallupNotifications.KEY_IDEMPOTENCY));
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
