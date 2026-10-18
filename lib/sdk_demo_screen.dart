import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:videohub/videohub.dart';

/// Standalone walkthrough of the core VideoHub SDK primitives, each button
/// wired straight to the SDK call it demonstrates:
///
///  - `VideoHub.join`    - host join, with or without publishing anything
///  - `VideoHub.connect` - guest join (always viewer-only)
///  - `RoomSession.local.publish`/`unpublish` - audio/video on demand
///  - `VideoHub.leaveRoom`
///
/// Deliberately plain `StatefulWidget`/`setState`, not GetX, so each SDK
/// call reads directly rather than through a controller layer - see
/// [JoinScreen]/[RoomScreen] for the same feature set wired into a
/// production-style GetX UI.
class SdkDemoScreen extends StatefulWidget {
  const SdkDemoScreen({super.key});

  @override
  State<SdkDemoScreen> createState() => _SdkDemoScreenState();
}

class _SdkDemoScreenState extends State<SdkDemoScreen> {
  final _roomCtrl = TextEditingController(text: 'sdk-demo');

  RoomSession? _session;
  bool _busy = false;
  String? _error;
  String _log = '';

  @override
  void dispose() {
    _roomCtrl.dispose();
    super.dispose();
  }

  RoomSession get _requireSession {
    final session = _session;
    if (session == null) {
      throw StateError('No active session - join or connect first.');
    }
    return session;
  }

  /// Runs [action], surfacing success/failure in the log and error banner
  /// and toggling [_busy] around it - every button below is just this
  /// wrapped around one SDK call.
  Future<void> _guard(String label, Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      setState(() => _log = '$_log\n✓ $label'.trim());
    } catch (e) {
      setState(() {
        _error = '$label failed: $e';
        _log = '$_log\n✗ $label: $e'.trim();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _requestPermissions({required bool audio, required bool video}) async {
    final permissions = [
      if (audio) Permission.microphone,
      if (video) Permission.camera,
    ];
    if (permissions.isEmpty) return true;

    final statuses = await permissions.request();
    return statuses.values.every((status) => status.isGranted);
  }

  // ── 1. Join / connect ───────────────────────────────────────────────────

  /// Host join, publishing mic + camera immediately.
  Future<void> _joinWithAudioVideo() => _guard('join(audio: true, video: true)', () async {
        if (!await _requestPermissions(audio: true, video: true)) {
          throw StateError('Camera/microphone permission denied');
        }
        _session = await VideoHubSDK.videoHub.join(_roomCtrl.text.trim(), audio: true, video: true);
      });

  /// Host join, publishing nothing - a viewer who still holds publish
  /// rights and can start a stream later, unlike a guest.
  Future<void> _joinWithoutPublishing() => _guard('join(audio: false, video: false)', () async {
        _session = await VideoHubSDK.videoHub.join(_roomCtrl.text.trim());
      });

  /// Guest join via a subscribe-only token - always viewer-only, can never
  /// publish.
  Future<void> _connectAsGuest() => _guard('connect()', () async {
        _session = await VideoHubSDK.videoHub.connect(_roomCtrl.text.trim());
      });

  // ── 2. Publish / unpublish on demand ────────────────────────────────────

  Future<void> _publishAudio() => _guard('local.publish(audio: true)', () async {
        if (!await _requestPermissions(audio: true, video: false)) {
          throw StateError('Microphone permission denied');
        }
        await _requireSession.local.publish(audio: true);
      });

  Future<void> _publishVideo() => _guard('local.publish(video: true)', () async {
        if (!await _requestPermissions(audio: false, video: true)) {
          throw StateError('Camera permission denied');
        }
        await _requireSession.local.publish(video: true);
      });

  Future<void> _publishBoth() => _guard('local.publish(audio: true, video: true)', () async {
        if (!await _requestPermissions(audio: true, video: true)) {
          throw StateError('Camera/microphone permission denied');
        }
        await _requireSession.local.publish(audio: true, video: true);
      });

  Future<void> _unpublishAudio() =>
      _guard('local.unpublish(audio: true)', () => _requireSession.local.unpublish(audio: true));

  Future<void> _unpublishVideo() =>
      _guard('local.unpublish(video: true)', () => _requireSession.local.unpublish(video: true));

  Future<void> _unpublishAll() => _guard('local.unpublishAll()', () => _requireSession.local.unpublishAll());

  // ── 3. Leave ─────────────────────────────────────────────────────────────

  Future<void> _leave() => _guard('leaveRoom()', () async {
        VideoHubSDK.videoHub.leaveRoom(_requireSession.roomName);
        _session = null;
      });

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final connected = session != null;

    return Scaffold(
      appBar: AppBar(title: const Text('SDK Primitives Demo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _roomCtrl,
              enabled: !connected,
              decoration: const InputDecoration(labelText: 'Room name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            if (session != null) _StatusChips(session: session),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 16),
            Text('1. Enter the room', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ActionButton('join() - host, audio+video', connected || _busy ? null : _joinWithAudioVideo),
                _ActionButton(
                    'join() - host, no publish (viewer)', connected || _busy ? null : _joinWithoutPublishing),
                _ActionButton('connect() - guest (viewer)', connected || _busy ? null : _connectAsGuest),
              ],
            ),
            const SizedBox(height: 20),
            Text('2. Publish / unpublish on demand', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ActionButton('Publish audio', !connected || _busy ? null : _publishAudio),
                _ActionButton('Publish video', !connected || _busy ? null : _publishVideo),
                _ActionButton('Publish both', !connected || _busy ? null : _publishBoth),
                _ActionButton('Unpublish audio', !connected || _busy ? null : _unpublishAudio),
                _ActionButton('Unpublish video', !connected || _busy ? null : _unpublishVideo),
                _ActionButton('Unpublish all', !connected || _busy ? null : _unpublishAll),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: !connected || _busy ? null : _leave,
              icon: const Icon(Icons.call_end),
              label: const Text('leaveRoom()'),
            ),
            const SizedBox(height: 16),
            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: 16),
            Text('Log', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                child: SingleChildScrollView(
                  reverse: true,
                  child: Text(
                    _log.isEmpty ? 'No calls made yet.' : _log,
                    style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live mic/camera/connection state, reactive off the same
/// `ChangeNotifier`s the video-tile widgets elsewhere in this example use -
/// proof that `publish`/`unpublish` actually flip published state, not just
/// that the calls didn't throw.
class _StatusChips extends StatelessWidget {
  const _StatusChips({required this.session});

  final RoomSession session;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([session.room, session.local.participant]),
      builder: (context, _) {
        final local = session.local;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text('State: ${session.sessionState.name}')),
            Chip(
              avatar: Icon(local.isMicrophoneEnabled ? Icons.mic : Icons.mic_off, size: 18),
              label: Text('Mic ${local.isMicrophoneEnabled ? 'on' : 'off'}'),
            ),
            Chip(
              avatar: Icon(local.isCameraEnabled ? Icons.videocam : Icons.videocam_off, size: 18),
              label: Text('Camera ${local.isCameraEnabled ? 'on' : 'off'}'),
            ),
          ],
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton(this.label, this.onPressed);

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(onPressed: onPressed, child: Text(label));
}
