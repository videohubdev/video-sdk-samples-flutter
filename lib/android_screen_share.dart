import 'dart:io' show Platform;

import 'package:flutter_background/flutter_background.dart';
import 'package:videohub/videohub.dart';

/// Android 14+ throws `SecurityException: Media projections require a
/// foreground service of type ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_
/// PROJECTION` unless a foreground service of that type is already running
/// before screen capture starts. The SDK doesn't start this service on the
/// app's behalf - see the package README's Android screen-share setup
/// section - so it's the host app's job, which is what this does before
/// `local.setScreenShareEnabled(true)` runs on Android. Capture permission
/// itself is still requested through the SDK
/// ([Local.requestScreenCapturePermission]), not a direct livekit_client/
/// flutter_webrtc import.
///
/// No-op (returns `true`) on every other platform. Requires the
/// `de.julianassmann.flutter_background.IsolateHolderService` service to be
/// declared in `AndroidManifest.xml` with
/// `android:foregroundServiceType="mediaProjection"` - see this example's
/// manifest.
Future<bool> prepareAndroidScreenShare(Local local) async {
  if (!Platform.isAndroid) return true;

  if (!await local.requestScreenCapturePermission()) return false;

  try {
    var hasPermissions = await FlutterBackground.hasPermissions;
    if (!hasPermissions) {
      hasPermissions = await FlutterBackground.initialize(
        androidConfig: const FlutterBackgroundAndroidConfig(
          notificationTitle: 'Screen sharing',
          notificationText: 'This app is sharing your screen.',
          notificationImportance: AndroidNotificationImportance.normal,
        ),
      );
    }
    if (!hasPermissions) return false;

    if (!FlutterBackground.isBackgroundExecutionEnabled) {
      await FlutterBackground.enableBackgroundExecution();
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// Stops the foreground service started by [prepareAndroidScreenShare],
/// once screen sharing ends. No-op on every other platform, or if it was
/// never started.
Future<void> teardownAndroidScreenShare() async {
  if (!Platform.isAndroid) return;
  if (!FlutterBackground.isBackgroundExecutionEnabled) return;
  await FlutterBackground.disableBackgroundExecution();
}
