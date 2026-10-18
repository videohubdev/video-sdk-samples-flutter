import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:videohub/videohub.dart';

/// Audio-only group voice call: the camera is never requested or
/// published. The whole feature is one call:
/// `VideoHubSDK.videoHub.join(roomName, audio: true, video: false)`.
///
/// Mute/unmute on demand goes through `RoomSession.local.publish`/
/// `unpublish` - the same on-demand API a video room uses, just called with
/// `audio:` instead of `video:`.
class AudioOnlyExample extends StatefulWidget {
  const AudioOnlyExample({super.key});

  @override
  State<AudioOnlyExample> createState() => _AudioOnlyExampleState();
}

class _AudioOnlyExampleState extends State<AudioOnlyExample> {
  final _roomCtrl = TextEditingController(text: 'audio-only-demo');
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
      if (!await Permission.microphone.request().isGranted) {
        throw StateError('Microphone permission is required.');
      }

      // Audio only - camera never requested or published.
      final session = await VideoHubSDK.videoHub.join(
        _roomCtrl.text.trim(),
        audio: true,
        video: false,
      );
      setState(() => _session = session);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleMute(RoomSession session, bool currentlyMuted) async {
    currentlyMuted ? await session.local.publish(audio: true) : await session.local.unpublish(audio: true);
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
      appBar: AppBar(title: const Text('Audio-only Example')),
      body: session == null ? _buildJoinForm(context) : _buildCall(session),
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
                : const Text('Join voice call'),
          ),
        ],
      ),
    );
  }

  Widget _buildCall(RoomSession session) {
    return AnimatedBuilder(
      // session.room covers roster/track changes; session.local.participant
      // is merged in too so the local mic icon updates immediately on
      // toggle, without waiting on a round-trip room-level event.
      animation: Listenable.merge([session.room, session.local.participant]),
      builder: (context, _) {
        final participants = [session.local, ...session.remote.participants.values.map(session.remote.moderation)];

        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final p in participants)
                    ListTile(
                      leading: CircleAvatar(child: Icon(p.isSpeaking ? Icons.record_voice_over : Icons.person)),
                      title: Text(p == session.local ? 'You' : p.identity),
                      trailing: Icon(p.isMicrophoneEnabled ? Icons.mic : Icons.mic_off),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filled(
                    onPressed: () => _toggleMute(session, !session.local.isMicrophoneEnabled),
                    icon: Icon(session.local.isMicrophoneEnabled ? Icons.mic : Icons.mic_off),
                  ),
                  const SizedBox(width: 16),
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
