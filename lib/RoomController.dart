import 'dart:async';

import 'package:get/get.dart';
import 'package:videohub/videohub.dart';

import 'android_screen_share.dart';

/// GetX controller backing [RoomScreen]: owns the live [RoomSession]
/// listeners - `session.room` (a `ChangeNotifier`) for roster/track changes,
/// and `session.observeEvents()` for lifecycle events like reconnects and
/// the server ending the call - plus the mic/camera/leaving UI state.
class RoomController extends GetxController {
  RoomController(this.session);

  final RoomSession session;

  StreamSubscription<VideoHubEvent>? _eventSub;

  late final sessionState = session.sessionState.obs;
  // Reflects whatever was actually published at join time - not assumed -
  // since `join()`/`connect()` can start a participant as a pure viewer
  // (nothing published) or audio-only, not just "both on".
  late final micOn = session.local.isMicrophoneEnabled.obs;
  late final cameraOn = session.local.isCameraEnabled.obs;
  late final screenSharing = session.local.isScreenShareEnabled.obs;
  final leaving = false.obs;
  final roomTick = 0.obs;

  Local get local => session.local;
  Remote get remote => session.remote;
  String get roomName => session.roomName;

  List<RemoteParticipant> get remoteParticipants =>
      remote.participants.values.toList(growable: false);

  @override
  void onInit() {
    super.onInit();
    session.room.addListener(_onRoomChanged);
    _eventSub = session.observeEvents().listen(_onEvent);
  }

  @override
  void onClose() {
    session.room.removeListener(_onRoomChanged);
    unawaited(_eventSub?.cancel());
    super.onClose();
  }

  void _onRoomChanged() => roomTick.value++;

  void _onEvent(VideoHubEvent event) {
    if (event is VideoHubDisconnected && !leaving.value) {
      // The server ended the call, or the connection dropped for good -
      // back out to the join screen rather than showing a dead grid.
      Get.until((route) => route.isFirst);
      return;
    }
    sessionState.value = session.sessionState;
  }

  Future<void> toggleMic() async {
    final next = !micOn.value;
    next ? await local.publish(audio: true) : await local.unpublish(audio: true);
    micOn.value = next;
  }

  Future<void> toggleCamera() async {
    final next = !cameraOn.value;
    next ? await local.publish(video: true) : await local.unpublish(video: true);
    cameraOn.value = next;
  }

  /// Starts/stops sharing the screen - a third, independent publish
  /// source alongside mic/camera. Triggers the platform's screen-capture
  /// permission prompt when turning on. On Android this also starts/stops
  /// the foreground service the platform requires to be running before
  /// screen capture can start (see android_screen_share.dart).
  Future<void> toggleScreenShare() async {
    final next = !screenSharing.value;

    if (next) {
      if (!await prepareAndroidScreenShare(local)) return;
      await local.publish(screen: true);
    } else {
      await local.unpublish(screen: true);
      await teardownAndroidScreenShare();
    }

    screenSharing.value = next;
  }

  /// Drops back to a pure viewer, unpublishing every track at once.
  Future<void> unpublishAll() async {
    await local.unpublishAll();
    micOn.value = false;
    cameraOn.value = false;
    if (screenSharing.value) await teardownAndroidScreenShare();
    screenSharing.value = false;
  }

  Future<void> switchCamera() => local.switchCamera();

  Future<void> leave() async {
    leaving.value = true;
    VideoHubSDK.videoHub.leaveRoom(roomName);
    Get.back();
  }
}
