package se.teamzone.notifications;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

/**
 * Shows TeamZone's notifications (also from the FCM background handler, which
 * runs without an activity) and reports the route of a tapped notification.
 */
public final class TeamzoneNotificationsPlugin
    implements FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
        PluginRegistry.NewIntentListener, EventChannel.StreamHandler {
  private Context context;
  private MethodChannel methods;
  private EventChannel opened;
  private EventChannel.EventSink openedSink;
  private ActivityPluginBinding activity;
  private String launchRoute;

  @Override
  public void onAttachedToEngine(FlutterPluginBinding binding) {
    context = binding.getApplicationContext();
    methods = new MethodChannel(binding.getBinaryMessenger(), "teamzone/notifications");
    methods.setMethodCallHandler(this);
    opened = new EventChannel(binding.getBinaryMessenger(), "teamzone/notifications/opened");
    opened.setStreamHandler(this);
  }

  @Override
  public void onDetachedFromEngine(FlutterPluginBinding binding) {
    methods.setMethodCallHandler(null);
    opened.setStreamHandler(null);
  }

  @Override
  public void onMethodCall(MethodCall call, MethodChannel.Result result) {
    switch (call.method) {
      case "createChannel":
        CallupNotifications.createChannel(context, call.argument("name"),
            call.argument("description"));
        result.success(null);
        break;
      case "showPlain":
        CallupNotifications.showPlain(context, call.<Integer>argument("id"),
            call.argument("title"), call.argument("body"), call.argument("route"));
        result.success(null);
        break;
      case "showCallup":
        CallupNotifications.showCallup(context, actionValues(call), call.argument("acceptLabel"),
            call.argument("declineLabel"), call.argument("declineRoute"));
        result.success(null);
        break;
      case "showMessage":
        CallupNotifications.showMessage(context, actionValues(call), call.argument("replyLabel"),
            call.argument("replyHint"));
        result.success(null);
        break;
      case "takeLaunchRoute":
        String route = launchRoute;
        launchRoute = null;
        result.success(route);
        break;
      default:
        result.notImplemented();
    }
  }

  @Override
  public void onAttachedToActivity(ActivityPluginBinding binding) {
    activity = binding;
    binding.addOnNewIntentListener(this);
    Activity current = binding.getActivity();
    launchRoute = routeOf(current.getIntent());
    // Consumed: a configuration change must not reopen the same page.
    current.getIntent().removeExtra(CallupNotifications.EXTRA_ROUTE);
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    onDetachedFromActivity();
  }

  @Override
  public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {
    activity = binding;
    binding.addOnNewIntentListener(this);
  }

  @Override
  public void onDetachedFromActivity() {
    if (activity != null) activity.removeOnNewIntentListener(this);
    activity = null;
  }

  @Override
  public boolean onNewIntent(Intent intent) {
    String route = routeOf(intent);
    if (route == null) return false;
    if (openedSink != null) {
      openedSink.success(route);
    } else {
      launchRoute = route;
    }
    return true;
  }

  @Override
  public void onListen(Object arguments, EventChannel.EventSink events) {
    openedSink = events;
  }

  @Override
  public void onCancel(Object arguments) {
    openedSink = null;
  }

  /** What the action receiver needs, from the Dart call. */
  private static Bundle actionValues(MethodCall call) {
    Bundle values = new Bundle();
    values.putInt(CallupNotifications.KEY_ID, call.<Integer>argument("id"));
    for (String key : new String[] {
        CallupNotifications.KEY_TITLE, CallupNotifications.KEY_BODY,
        CallupNotifications.KEY_ROUTE, CallupNotifications.KEY_TOKEN,
        CallupNotifications.KEY_IDEMPOTENCY, CallupNotifications.KEY_ENDPOINT,
        CallupNotifications.KEY_API_KEY, CallupNotifications.KEY_SENT,
        CallupNotifications.KEY_GONE, CallupNotifications.KEY_FAILED,
        CallupNotifications.KEY_LOCKED}) {
      values.putString(key, call.argument(key));
    }
    return values;
  }

  private static String routeOf(Intent intent) {
    return intent == null ? null : intent.getStringExtra(CallupNotifications.EXTRA_ROUTE);
  }
}
