import 'dart:async';

import 'package:get/get.dart';
import 'package:videohub/videohub.dart';

import 'android_screen_share.dart';

/// GetX controller backing [CallScreen]: owns the live [RoomSession]
/// listeners (mirrors [RoomController]) plus the call-specific moderation
/// actions - mute/camera-off/kick the other participant, and end the call
/// server-side - routed through `VideoHubSDK.videoHub.call`.
class CallController extends GetxController {
  CallController(this.session);

  final RoomSession session;

  StreamSubscription<VideoHubEvent>? _eventSub;

  late final sessionState = session.sessionState.obs;
  // Reflects whatever was actually published at join time, not assumed.
  late final micOn = session.local.isMicrophoneEnabled.obs;
  late final cameraOn = session.local.isCameraEnabled.obs;
  late final screenSharing = session.local.isScreenShareEnabled.obs;
  final otherMuted = false.obs;
  final otherVideoOff = false.obs;
  final leaving = false.obs;
  final roomTick = 0.obs;

  Local get local => session.local;
  Remote get remote => session.remote;
  String get roomName => session.roomName;
  Call get _call => VideoHubSDK.videoHub.call;

  /// Identifier of this call - share it with whoever should join as
  /// callee via `Call.join(callId)`. Set for both sides (caller and
  /// callee) before the session is even connected, so it's always
  /// available by the time [CallScreen] builds.
  String? get callId => _call.callId;

  /// The other participant in the call, if they've joined yet.
  RemoteParticipant? get other {
    final participants = remote.participants.values;
    return participants.isEmpty ? null : participants.first;
  }

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
      // The other participant ended the call, or the connection dropped
      // for good - back out rather than showing a dead screen.
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

  Future<void> switchCamera() => local.switchCamera();

  /// Starts/stops sharing the local screen in the call. On Android this
  /// also starts/stops the foreground service the platform requires to be
  /// running before screen capture can start (see android_screen_share.dart).
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

  /// Mutes/unmutes the other participant (server-side call moderation, not
  /// just local playback).
  Future<void> toggleOtherMute() async {
    final next = !otherMuted.value;
    await _call.mute(next);
    otherMuted.value = next;
  }

  /// Disables/re-enables the other participant's camera.
  Future<void> toggleOtherVideo() async {
    final next = !otherVideoOff.value;
    await _call.videoOff(next);
    otherVideoOff.value = next;
  }

  /// Stops the other participant's screen share.
  Future<void> stopOtherScreenShare() => _call.screenOff();

  /// Removes the other participant from the call. The call itself stays
  /// active - use [endCall] to end it entirely.
  Future<void> kickOther() => _call.kick();

  /// Ends the call server-side and leaves the local room session.
  Future<void> endCall() async {
    leaving.value = true;
    await _call.end();
    VideoHubSDK.videoHub.leaveRoom(roomName);
    Get.back();
  }
}
