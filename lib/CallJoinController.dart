import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:videohub/videohub.dart';

import 'call_screen.dart';

/// GetX controller backing [CallJoinScreen]: starts a 1:1 call as the
/// caller, or joins one as the callee, then hands the resulting
/// [RoomSession] off to [CallScreen].
class CallJoinController extends GetxController {
  final callerIdCtrl = TextEditingController(text: 'caller_1');
  final calleeIdCtrl = TextEditingController(text: 'callee_1');
  final callIdCtrl = TextEditingController();

  final busy = false.obs;
  final error = RxnString();

  @override
  void onClose() {
    callerIdCtrl.dispose();
    calleeIdCtrl.dispose();
    callIdCtrl.dispose();
    super.onClose();
  }

  Future<bool> _requestMediaPermissions() async {
    final statuses = await [Permission.camera, Permission.microphone].request();
    return statuses.values.every((status) => status.isGranted);
  }

  Future<void> startCall(BuildContext context) async {
    final callerId = callerIdCtrl.text.trim();
    final calleeId = calleeIdCtrl.text.trim();
    if (callerId.isEmpty || calleeId.isEmpty) return;

    await _run(context, () {
      return VideoHubSDK.videoHub.call.start(
        callerId,
        calleeId,
        audio: true,
        video: true,
      );
    });
  }

  Future<void> joinCall(BuildContext context) async {
    final callId = callIdCtrl.text.trim();
    if (callId.isEmpty) return;

    await _run(context, () {
      return VideoHubSDK.videoHub.call.join(
        callId,
        audio: true,
        video: true,
      );
    });
  }

  Future<void> _run(BuildContext context, Future<RoomSession> Function() action) async {
    busy.value = true;
    error.value = null;

    try {
      if (!await _requestMediaPermissions()) {
        throw StateError('Camera and microphone permissions are required for a call.');
      }

      final session = await action();

      if (!context.mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => CallScreen(session: session)),
      );
    } catch (e) {
      error.value = '$e';
    } finally {
      busy.value = false;
    }
  }
}
