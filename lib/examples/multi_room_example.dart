import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:videohub/videohub.dart';

import 'simple_tile.dart';

/// Joining more than one room at once - VideoHub tracks sessions as peers,
/// not a single "active room", so two `join()`/`connect()` calls for
/// different room names both stay live until each is left independently
/// (see `VideoHubSDK.videoHub.sessions` for the full registry). The two
/// [_RoomSlot]s below are completely independent `RoomSession`s; leaving
/// one never touches the other.
class MultiRoomExample extends StatelessWidget {
  const MultiRoomExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Multi-room Example')),
      body: const Padding(
        padding: EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(child: _RoomSlot(defaultRoomName: 'multi-room-a')),
            SizedBox(width: 8),
            Expanded(child: _RoomSlot(defaultRoomName: 'multi-room-b')),
          ],
        ),
      ),
    );
  }
}

class _RoomSlot extends StatefulWidget {
  const _RoomSlot({required this.defaultRoomName});

  final String defaultRoomName;

  @override
  State<_RoomSlot> createState() => _RoomSlotState();
}

class _RoomSlotState extends State<_RoomSlot> {
  late final _roomCtrl = TextEditingController(text: widget.defaultRoomName);
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
        throw StateError('Camera/microphone permission required.');
      }

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
    // Only this slot's room is affected - the other slot's session (if
    // any) keeps running untouched.
    VideoHubSDK.videoHub.leaveRoom(session.roomName);
    setState(() => _session = null);
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;

    return Column(
      children: [
        TextField(
          controller: _roomCtrl,
          enabled: session == null,
          decoration: const InputDecoration(labelText: 'Room name', border: OutlineInputBorder(), isDense: true),
        ),
        const SizedBox(height: 8),
        if (_error != null)
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
        Expanded(
          child: session == null
              ? Center(
                  child: _busy
                      ? const CircularProgressIndicator()
                      : FilledButton(onPressed: _join, child: const Text('Join')),
                )
              : AnimatedBuilder(
                  animation: session.room,
                  builder: (context, _) => SimpleParticipantTile(
                    participant: session.local,
                    label: '${session.roomName} (you)',
                    isLocal: true,
                  ),
                ),
        ),
        const SizedBox(height: 8),
        if (session != null)
          OutlinedButton.icon(onPressed: _leave, icon: const Icon(Icons.call_end), label: const Text('Leave')),
      ],
    );
  }
}
