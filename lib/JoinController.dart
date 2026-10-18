
import 'package:flutter/material.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:get/get_state_manager/src/simple/get_controllers.dart';
// import 'package:group_video_chat_example/room_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:videohub/videohub.dart';

import 'room_screen.dart';

/// What a host publishes immediately on join - the demo's stand-in for the
/// "group audio call" / "viewer-only" / "on-demand" feature set: every mode
/// still lands in the same [RoomSession], just with different tracks (or
/// none) published up front. Publishing can always change later through
/// `RoomSession.local.publish`/`unpublish` - see [RoomController].
enum HostJoinMode {
  audioAndVideo('Audio + video'),
  audioOnly('Audio only (group voice call)'),
  viewer('Viewer (publish nothing, join to watch/listen)');

  const HostJoinMode(this.label);
  final String label;
}

/// GetX controller backing [JoinScreen]: holds the room-name field and the
/// busy/error state, and drives the create-as-host / join-as-guest flow.
class JoinController extends GetxController {
  final roomCtrl = TextEditingController(text: 'group-demo');
  final joinMode = HostJoinMode.audioAndVideo.obs;
  final busy = false.obs;
  final error = RxnString();

  @override
  void onClose() {
    roomCtrl.dispose();
    super.onClose();
  }

  Future<bool> _requestMediaPermissions({required bool audio, required bool video}) async {
    final permissions = [
      if (audio) Permission.microphone,
      if (video) Permission.camera,
    ];
    if (permissions.isEmpty) return true;

    final statuses = await permissions.request();
    return statuses.values.every((status) => status.isGranted);
  }

  Future<void> join(BuildContext context, {required bool asHost}) async {
    final roomName = roomCtrl.text.trim();
    if (roomName.isEmpty) return;

    busy.value = true;
    error.value = null;

    try {
      // Guests always join as pure viewers - the server issues them a
      // subscribe-only token, so there's nothing to request permission for.
      final mode = asHost ? joinMode.value : HostJoinMode.viewer;
      final wantAudio = mode == HostJoinMode.audioAndVideo || mode == HostJoinMode.audioOnly;
      final wantVideo = mode == HostJoinMode.audioAndVideo;

      if (asHost && !await _requestMediaPermissions(audio: wantAudio, video: wantVideo)) {
        throw StateError('Camera/microphone permission is required for "${mode.label}".');
      }

      final session = asHost
          ? await VideoHubSDK.videoHub.join(roomName, audio: wantAudio, video: wantVideo)
          : await VideoHubSDK.videoHub.connect(roomName);

      if (!context.mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => RoomScreen(session: session)),
      );
    } catch (e) {
      error.value = '$e';
    } finally {
      busy.value = false;
    }
  }
}