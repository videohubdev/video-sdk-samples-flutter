import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:videohub/videohub.dart';

import 'simple_tile.dart';

/// Video-only group room: publishes the camera but never the microphone -
/// e.g. a silent broadcast / security-style feed. The whole feature is one
/// call: `VideoHubSDK.videoHub.join(roomName, audio: false, video: true)`.
class VideoOnlyExample extends StatefulWidget {
  const VideoOnlyExample({super.key});

  @override
  State<VideoOnlyExample> createState() => _VideoOnlyExampleState();
}

class _VideoOnlyExampleState extends State<VideoOnlyExample> {
  final _roomCtrl = TextEditingController(text: 'video-only-demo');
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
      if (!await Permission.camera.request().isGranted) {
        throw StateError('Camera permission is required.');
      }

      // Video only - no microphone requested or published.
      final session = await VideoHubSDK.videoHub.join(
        _roomCtrl.text.trim(),
        audio: false,
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
      appBar: AppBar(title: const Text('Video-only Example')),
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
                : const Text('Join (video only)'),
          ),
        ],
      ),
    );
  }

  Widget _buildRoom(RoomSession session) {
    return AnimatedBuilder(
      animation: session.room,
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
              child: FilledButton.icon(onPressed: _leave, icon: const Icon(Icons.call_end), label: const Text('Leave')),
            ),
          ],
        );
      },
    );
  }
}
