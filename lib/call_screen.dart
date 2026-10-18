import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:get/get.dart';
import 'package:videohub/videohub.dart';

import 'CallController.dart';

/// 1:1 call surface: local + other-participant video tiles, mic/camera
/// controls for the local side, and call moderation controls (mute/camera-
/// off/kick/end) for the other side, driven entirely by [CallController].
class CallScreen extends StatefulWidget {
  const CallScreen({required this.session, super.key});

  final RoomSession session;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late final CallController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(CallController(widget.session), tag: widget.session.roomName);
  }

  @override
  void dispose() {
    Get.delete<CallController>(tag: widget.session.roomName);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) controller.endCall();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Call'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Obx(() => _StatusPill(state: controller.sessionState.value)),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (controller.callId case final callId?) _CallIdBar(callId: callId),
              Expanded(
                child: Obx(() {
                  controller.roomTick.value;
                  final other = controller.other;
                  return _CallTiles(
                    local: controller.local,
                    other: other == null ? null : controller.remote.moderation(other),
                  );
                }),
              ),
            ],
          ),
        ),
        bottomNavigationBar: ColoredBox(
          color: Colors.black,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Obx(
                        () => _ControlButton(
                          icon: controller.micOn.value ? Icons.mic : Icons.mic_off,
                          onPressed: controller.toggleMic,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Obx(
                        () => _ControlButton(
                          icon: controller.cameraOn.value ? Icons.videocam : Icons.videocam_off,
                          onPressed: controller.toggleCamera,
                        ),
                      ),
                      const SizedBox(width: 16),
                      _ControlButton(icon: Icons.cameraswitch, onPressed: controller.switchCamera),
                      const SizedBox(width: 16),
                      Obx(
                        () => _ControlButton(
                          icon: controller.screenSharing.value ? Icons.stop_screen_share : Icons.screen_share,
                          onPressed: controller.toggleScreenShare,
                        ),
                      ),
                      const SizedBox(width: 16),
                      _ControlButton(
                        icon: Icons.call_end,
                        background: Colors.red,
                        onPressed: controller.endCall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Obx(
                          () => _ModerationChip(
                            label: controller.otherMuted.value ? 'Unmute other' : 'Mute other',
                            icon: Icons.mic_off,
                            onPressed: controller.toggleOtherMute,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Obx(
                          () => _ModerationChip(
                            label: controller.otherVideoOff.value ? 'Enable their cam' : 'Disable their cam',
                            icon: Icons.videocam_off,
                            onPressed: controller.toggleOtherVideo,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _ModerationChip(
                          label: 'Stop their screen share',
                          icon: Icons.stop_screen_share,
                          onPressed: controller.stopOtherScreenShare,
                        ),
                        const SizedBox(width: 8),
                        _ModerationChip(
                          label: 'Kick',
                          icon: Icons.person_remove,
                          onPressed: controller.kickOther,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the call id and copies it to the clipboard on tap - share it with
/// whoever should join as callee via `Call.join(callId)`.
class _CallIdBar extends StatelessWidget {
  const _CallIdBar({required this.callId});

  final String callId;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white10,
      child: InkWell(
        onTap: () => _copy(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.tag, size: 16, color: Colors.white70),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Call ID: $callId',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.copy, size: 16, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: callId));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Call ID copied'), duration: Duration(seconds: 1)));
  }
}

class _CallTiles extends StatelessWidget {
  const _CallTiles({required this.local, required this.other});

  final Local local;
  final RemoteItem? other;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Expanded(
            child: other == null
                ? const _WaitingTile()
                : _ParticipantTile(label: other!.identity, isLocal: false, participant: other!),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: Row(
              children: [
                Expanded(
                  child: _ParticipantTile(label: 'You', isLocal: true, participant: local),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WaitingTile extends StatelessWidget {
  const _WaitingTile();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: const Color(0xFF1E1E1E),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white54),
              SizedBox(height: 12),
              Text('Waiting for the other participant…', style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.label,
    required this.isLocal,
    required this.participant,
  });

  final String label;
  final bool isLocal;
  final BaseParticipant participant;

  @override
  Widget build(BuildContext context) {
    // The participant's ChangeNotifier already covers track publish/mute
    // changes, so listening here keeps the tile's video and mic icon in
    // sync without a dedicated stream per field.
    return AnimatedBuilder(
      animation: participant.participant,
      builder: (context, _) {
        final track = participant.preferredVideoTrack();

        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ColoredBox(
            color: const Color(0xFF1E1E1E),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (track != null)
                  VideoTrackRenderer(
                    track,
                    mirrorMode: isLocal ? VideoViewMirrorMode.mirror : VideoViewMirrorMode.off,
                  )
                else
                  const Center(child: Icon(Icons.person, size: 48, color: Colors.white54)),
                Positioned(
                  left: 8,
                  bottom: 8,
                  right: 8,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        participant.isMicrophoneEnabled ? Icons.mic : Icons.mic_off,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          label,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({required this.icon, required this.onPressed, this.background});

  final IconData icon;
  final VoidCallback onPressed;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: background ?? Colors.white24,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.all(16),
      ),
    );
  }
}

class _ModerationChip extends StatelessWidget {
  const _ModerationChip({required this.label, required this.icon, required this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: Colors.white),
      label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      backgroundColor: Colors.white24,
      onPressed: onPressed,
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.state});

  final RoomSessionState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      RoomSessionState.connected || RoomSessionState.reconnected => ('Live', Colors.green),
      RoomSessionState.connecting => ('Connecting', Colors.orange),
      RoomSessionState.reconnecting => ('Reconnecting', Colors.orange),
      RoomSessionState.disconnecting => ('Leaving', Colors.grey),
      RoomSessionState.disconnected => ('Disconnected', Colors.grey),
      RoomSessionState.error => ('Error', Colors.red),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
