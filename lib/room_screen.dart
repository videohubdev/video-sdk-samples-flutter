import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:videohub/videohub.dart';

import 'RoomController.dart';

/// Group call surface: a responsive participant grid plus mic/camera/leave
/// controls. All session/UI state lives in [RoomController]; this widget
/// (and its `State`) only wires the controller's lifecycle to the route and
/// renders what it exposes.
class RoomScreen extends StatefulWidget {
  const RoomScreen({required this.session, super.key});

  final RoomSession session;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  late final RoomController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(RoomController(widget.session), tag: widget.session.roomName);
  }

  @override
  void dispose() {
    Get.delete<RoomController>(tag: widget.session.roomName);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) controller.leave();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(controller.roomName),
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
          child: Obx(() {
            controller.roomTick.value;
            final sharer = _findScreenSharer(controller);

            return Column(
              children: [
                if (sharer != null) ...[
                  Expanded(flex: 3, child: _ScreenShareTile(participant: sharer)),
                  const SizedBox(height: 8),
                ],
                Expanded(
                  flex: sharer != null ? 2 : 5,
                  child: _ParticipantGrid(
                    local: controller.local,
                    remote: controller.remote,
                    remoteParticipants: controller.remoteParticipants,
                  ),
                ),
              ],
            );
          }),
        ),
        bottomNavigationBar: ColoredBox(
          color: Colors.black,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
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
                  _ControlButton(
                    icon: Icons.cameraswitch,
                    onPressed: controller.switchCamera,
                  ),
                  const SizedBox(width: 16),
                  Obx(
                    () => _ControlButton(
                      icon: controller.screenSharing.value ? Icons.stop_screen_share : Icons.screen_share,
                      tooltip: controller.screenSharing.value ? 'Stop screen share' : 'Share screen',
                      onPressed: controller.toggleScreenShare,
                    ),
                  ),
                  const SizedBox(width: 16),
                  _ControlButton(
                    icon: Icons.visibility_off,
                    tooltip: 'Become a viewer (unpublish everything)',
                    onPressed: controller.unpublishAll,
                  ),
                  const SizedBox(width: 16),
                  _ControlButton(
                    icon: Icons.call_end,
                    background: Colors.red,
                    onPressed: controller.leave,
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

/// Whoever is currently sharing their screen - local checked first, since
/// only one screen share is typically live at a time. Returns null when
/// nobody is sharing.
BaseParticipant? _findScreenSharer(RoomController controller) {
  if (controller.local.isScreenShareEnabled) return controller.local;

  for (final p in controller.remoteParticipants) {
    final item = controller.remote.moderation(p);
    if (item.isScreenShareEnabled) return item;
  }

  return null;
}

/// The "screen track render option" in practice: explicitly renders
/// [BaseParticipant.screenShareTrack] rather than [preferredVideoTrack],
/// as a dedicated full-width tile separate from the camera grid below -
/// and with [VideoViewFit.contain] rather than the grid's default cover
/// fit, since screen content should never be cropped.
class _ScreenShareTile extends StatelessWidget {
  const _ScreenShareTile({required this.participant});

  final BaseParticipant participant;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: participant.participant,
      builder: (context, _) {
        final track = participant.screenShareTrack;

        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (track != null)
                  VideoTrackRenderer(track, fit: VideoViewFit.contain)
                else
                  const Center(child: Icon(Icons.screen_share, color: Colors.white54, size: 40)),
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      '${participant.identity} is sharing their screen',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
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

class _ParticipantGrid extends StatelessWidget {
  const _ParticipantGrid({
    required this.local,
    required this.remote,
    required this.remoteParticipants,
  });

  final Local local;
  final Remote remote;
  final List<RemoteParticipant> remoteParticipants;

  @override
  Widget build(BuildContext context) {
    final tileCount = remoteParticipants.length + 1;
    final columns = tileCount <= 1
        ? 1
        : tileCount <= 4
            ? 2
            : 3;

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 3 / 4,
      ),
      itemCount: tileCount,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _ParticipantTile(
            label: 'You',
            isLocal: true,
            participant: local,
          );
        }

        final item = remote.moderation(remoteParticipants[index - 1]);
        return _ParticipantTile(
          label: item.identity,
          isLocal: false,
          participant: item,
        );
      },
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
        // The camera track specifically - screen share (if any) renders in
        // its own dedicated _ScreenShareTile above the grid instead.
        final track = participant.cameraTrack;

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
  const _ControlButton({required this.icon, required this.onPressed, this.background, this.tooltip});

  final IconData icon;
  final VoidCallback onPressed;
  final Color? background;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      onPressed: onPressed,
      icon: Icon(icon),
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: background ?? Colors.white24,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.all(16),
      ),
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
