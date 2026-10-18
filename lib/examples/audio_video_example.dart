import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:videohub/videohub.dart';

import 'simple_tile.dart';

/// Standard audio+video group room - both mic and camera publish
/// immediately on join: `VideoHubSDK.videoHub.join(roomName, audio: true,
/// video: true)`. See [VideoOnlyExample]/[AudioOnlyExample] for publishing
/// just one track, and `RoomSession.local.publish`/`unpublish` for
/// switching between them on demand after joining.
class AudioVideoExample extends StatefulWidget {
  const AudioVideoExample({super.key});

  @override
  State<AudioVideoExample> createState() => _AudioVideoExampleState();
}

class _AudioVideoExampleState extends State<AudioVideoExample> {
  final _roomCtrl = TextEditingController(text: 'audio-video-demo');
  RoomSession? _session;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _roomCtrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final statuses = await [Permission.camera, Permission.microphone].request();
      if (!statuses.values.every((status) => status.isGranted)) {
        throw StateError('Camera and microphone permissions are required.');
      }

      // Both audio and video publish immediately on join.
      final session = await VideoHubSDK.videoHub.join(
        _roomCtrl.text.trim(),
        audio: true,
        video: true,
      );
      setState(() => _session = session);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _leave() {
    final session = _session;
    if (session == null) return;
    VideoHubSDK.videoHub.leaveRoom(session.roomName);
    setState(() => _session = null);
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      appBar: AppBar(title: const Text('Audio + Video Example')),
      body: session == null ? _buildJoinForm(context) : _buildRoom(session),
    );
  }

  Widget _buildJoinForm(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _roomCtrl,
            decoration: const InputDecoration(labelText: 'Room name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          FilledButton(
            onPressed: _busy ? null : _join,
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Join (audio + video)'),
          ),
        ],
      ),
    );
  }

  Widget _buildRoom(RoomSession session) {
    return AnimatedBuilder(
      // session.room covers roster/track changes; session.local.participant
      // is merged in so the mic/camera buttons below update immediately on
      // toggle rather than waiting on a round-trip room-level event.
      animation: Listenable.merge([session.room, session.local.participant]),
      builder: (context, _) {
        final remote = session.remote.participants.values.map(session.remote.moderation);

        return Column(
          children: [
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                padding: const EdgeInsets.all(8),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  SimpleParticipantTile(participant: session.local, label: 'You', isLocal: true),
                  for (final item in remote) SimpleParticipantTile(participant: item, label: item.identity, isLocal: false),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filled(
                    onPressed: () => session.local.isMicrophoneEnabled
                        ? session.local.unpublish(audio: true)
                        : session.local.publish(audio: true),
                    icon: Icon(session.local.isMicrophoneEnabled ? Icons.mic : Icons.mic_off),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filled(
                    onPressed: () => session.local.isCameraEnabled
                        ? session.local.unpublish(video: true)
                        : session.local.publish(video: true),
                    icon: Icon(session.local.isCameraEnabled ? Icons.videocam : Icons.videocam_off),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(onPressed: _leave, icon: const Icon(Icons.call_end), label: const Text('Leave')),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
