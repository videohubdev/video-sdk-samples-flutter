import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:videohub/videohub.dart';

const _emojis = ['😀', '😂', '❤️', '👍', '🎉', '😮', '😢', '🙏', '🔥', '👏'];

/// A real chat screen (left/right bubbles) built on RTM, covering every
/// sub-namespace:
///  - Chat: text, rich/sticker messages, emoji, delete, reactions, typing,
///    raise hand - all rendered as bubbles, sent (right) vs. received
///    (left).
///  - Files: [RoomSession.attachment] does the actual upload/download with
///    progress; [Rtm.attachment] announces the result to the room so it
///    shows up as a file bubble for everyone, download button included.
///  - Moderation / screen-share signaling / call invite / presence & poll:
///    secondary actions that don't need their own bubble type, reached via
///    the toolbar's "Features" sheet.
///  - A raw event log (toolbar) shows every incoming frame via
///    `rtm.on(RtmEvent.all, ...)`, for events without a typed rendering.
class RtmExample extends StatefulWidget {
  const RtmExample({super.key});

  @override
  State<RtmExample> createState() => _RtmExampleState();
}

enum _ChatKind { text, rich, attachment, system }

class _ChatMessage {
  _ChatMessage({
    required this.id,
    required this.isMine,
    required this.kind,
    this.senderLabel = 'them',
    this.text,
    this.richPayload,
    this.attachment,
    this.uploadProgress,
  }) : time = DateTime.now();

  final String id;
  final bool isMine;
  final _ChatKind kind;
  final String senderLabel;
  final DateTime time;
  String? text;
  Map<String, dynamic>? richPayload;
  RtmAttachmentObject? attachment;
  int? uploadProgress;
  int? downloadProgress;
  File? localFile;
  String? reaction;
}

class _RtmExampleState extends State<RtmExample> {
  final _roomCtrl = TextEditingController(text: 'rtm-demo');
  final _messageCtrl = TextEditingController();

  final _targetUserCtrl = TextEditingController(text: 'user_123');
  final _streamIdCtrl = TextEditingController(text: 'screen-1');
  final _statusCtrl = TextEditingController(text: 'online');
  final _stateCtrl = TextEditingController(text: 'active');
  final _pollIdCtrl = TextEditingController(text: 'poll_1');
  final _optionIdCtrl = TextEditingController(text: 'option_a');

  RoomSession? _session;
  Rtm? _rtm;
  bool _busy = false;
  bool _showEmoji = false;
  String? _error;
  String? _typingLabel;
  Timer? _typingClearTimer;

  final List<_ChatMessage> _messages = [];
  final List<String> _rawLog = [];
  final List<(RtmEvent, void Function(Map<String, dynamic>?))> _registered = [];

  // The RTM server broadcasts to the whole room, sender included - so a
  // message/attachment we just sent optimistically (added locally,
  // isMine: true) also arrives back through the same rtm.on handlers a
  // moment later. These track our own ids so that echo is recognized and
  // dropped instead of appearing a second time as "theirs".
  final Set<String> _myMessageIds = {};
  final Set<String> _myAttachmentFileIds = {};

  @override
  void dispose() {
    _roomCtrl.dispose();
    _messageCtrl.dispose();
    _targetUserCtrl.dispose();
    _streamIdCtrl.dispose();
    _statusCtrl.dispose();
    _stateCtrl.dispose();
    _pollIdCtrl.dispose();
    _optionIdCtrl.dispose();
    _typingClearTimer?.cancel();
    super.dispose();
  }

  String get _roomName => _session!.roomName;

  int _nextLocalId = 0;
  String _localId() => 'local-${_nextLocalId++}';

  // ── Connect ──────────────────────────────────────────────────────────

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await VideoHubSDK.videoHub.join(_roomCtrl.text.trim());

      // Best-effort by design (see RoomSession.bindRtm) - check rtm/
      // isConnected afterward rather than expecting a thrown error.
      await session.bindRtm();
      final rtm = session.rtm;
      if (rtm == null || !rtm.isConnected) {
        throw StateError('RTM failed to connect - enable VideoHubConfig.debug for details.');
      }

      _wireHandlers(rtm);

      setState(() {
        _session = session;
        _rtm = rtm;
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _leave() {
    final rtm = _rtm;
    final session = _session;

    if (rtm != null) {
      for (final (event, handler) in _registered) {
        rtm.off(event, handler);
      }
      _registered.clear();
    }
    if (session != null) {
      // release() would tear this down too, but RTM has its own lifecycle
      // method for when a caller wants to drop just the signaling channel
      // and keep the RTC room - shown explicitly here for that reason.
      session.releaseRtm();
      VideoHubSDK.videoHub.leaveRoom(session.roomName);
    }

    setState(() {
      _session = null;
      _rtm = null;
      _messages.clear();
      _rawLog.clear();
      _typingLabel = null;
    });
  }

  // ── Incoming events ──────────────────────────────────────────────────

  void _on(Rtm rtm, RtmEvent event, void Function(Map<String, dynamic>?) handler) {
    rtm.on(event, handler);
    _registered.add((event, handler));
  }

  void _wireHandlers(Rtm rtm) {
    // Every frame, regardless of type - a raw log for events without a
    // dedicated bubble/handler below.
    _on(rtm, RtmEvent.all, (payload) {
      _rawLog.add('${payload?['event']}: ${payload?['payload']}');
    });

    _on(rtm, RtmEvent.chatMessage, (payload) {
      final message = payload?['message'] as String?;
      if (message == null) return;

      final id = payload?['message_id'] as String? ?? _localId();
      // The server echoes our own sends back to us too - skip, since it's
      // already shown (isMine: true) from the moment we sent it.
      if (_myMessageIds.contains(id)) return;

      final sender = _senderOf(payload);

      // sendRichMessage JSON-encodes its payload into this same `message`
      // field - decode-and-check is how a receiver tells rich from plain.
      Map<String, dynamic>? rich;
      try {
        final decoded = jsonDecode(message);
        if (decoded is Map<String, dynamic>) rich = decoded;
      } catch (_) {}

      setState(() {
        _messages.add(_ChatMessage(
          id: id,
          isMine: false,
          senderLabel: sender,
          kind: rich != null ? _ChatKind.rich : _ChatKind.text,
          text: rich == null ? message : null,
          richPayload: rich,
        ));
      });
    });

    _on(rtm, RtmEvent.chatAttachment, (payload) {
      final sender = _senderOf(payload);
      final attachments = payload?['attachments'] as List<dynamic>?;
      if (attachments == null) return;

      setState(() {
        for (final raw in attachments) {
          final map = raw as Map<String, dynamic>;
          final fileId = map['file_id'] as String?;
          // Same echo-back as chatMessage - our own announced attachment
          // is already shown from the moment the upload finished.
          if (fileId != null && _myAttachmentFileIds.contains(fileId)) continue;

          _messages.add(_ChatMessage(
            id: fileId ?? _localId(),
            isMine: false,
            senderLabel: sender,
            kind: _ChatKind.attachment,
            attachment: RtmAttachmentObject(
              fileId: map['file_id'] as String? ?? '',
              name: map['name'] as String? ?? 'file',
              size: (map['size'] as num?)?.toInt() ?? 0,
              mimeType: map['mime_type'] as String? ?? 'application/octet-stream',
              url: map['url'] as String?,
              thumbnailUrl: map['thumbnail_url'] as String?,
            ),
          ));
        }
      });
    });

    _on(rtm, RtmEvent.chatMessageDelete, (payload) {
      final id = payload?['message_id'] as String?;
      if (id == null) return;
      setState(() => _messages.removeWhere((m) => m.id == id));
    });

    _on(rtm, RtmEvent.reactionAdd, (payload) {
      final id = payload?['message_id'] as String?;
      final reaction = payload?['reaction'] as String?;
      if (id == null) return;
      setState(() {
        final match = _messages.where((m) => m.id == id);
        if (match.isNotEmpty) match.first.reaction = reaction;
      });
    });

    _on(rtm, RtmEvent.typingStart, (payload) {
      final sender = _senderOf(payload);
      setState(() => _typingLabel = '$sender is typing…');
      _typingClearTimer?.cancel();
      _typingClearTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _typingLabel = null);
      });
    });

    _on(rtm, RtmEvent.typingStop, (_) {
      _typingClearTimer?.cancel();
      setState(() => _typingLabel = null);
    });

    _on(rtm, RtmEvent.raiseHand, (payload) {
      final raised = payload?['raised'] == true;
      _addSystemLine('${_senderOf(payload)} ${raised ? 'raised' : 'lowered'} their hand');
    });

    // Events with no dedicated bubble - shown as a short, human-readable
    // system line (never the raw payload - that's what the debug log
    // sheet is for, see _openLogSheet/_describeEvent).
    for (final event in const [
      RtmEvent.userJoined,
      RtmEvent.userLeft,
      RtmEvent.userMute,
      RtmEvent.userKick,
      RtmEvent.screenShareStart,
      RtmEvent.screenShareStop,
      RtmEvent.callInvite,
      RtmEvent.callAccept,
      RtmEvent.callReject,
      RtmEvent.presenceUpdate,
      RtmEvent.pollVote,
    ]) {
      _on(rtm, event, (payload) => _addSystemLine(_describeEvent(event, payload)));
    }
  }

  String _senderOf(Map<String, dynamic>? payload) =>
      (payload?['user_id'] ?? payload?['sender_id'] ?? payload?['from'])?.toString() ?? 'them';

  /// A short, human-readable summary for events that don't have a
  /// dedicated bubble - only the field(s) relevant to that event, never
  /// the whole payload map. The full JSON is still available in the debug
  /// log sheet (see [_openLogSheet]), which logs every frame regardless.
  String _describeEvent(RtmEvent event, Map<String, dynamic>? payload) {
    final sender = _senderOf(payload);
    switch (event) {
      case RtmEvent.userJoined:
        return '$sender joined the room';
      case RtmEvent.userLeft:
        return '$sender left the room';
      case RtmEvent.userMute:
        return '${payload?['target_user_id'] ?? 'someone'} was muted';
      case RtmEvent.userKick:
        return '${payload?['target_user_id'] ?? 'someone'} was kicked';
      case RtmEvent.screenShareStart:
        return '$sender started screen sharing${_streamSuffix(payload)}';
      case RtmEvent.screenShareStop:
        return '$sender stopped screen sharing${_streamSuffix(payload)}';
      case RtmEvent.callInvite:
        return '$sender invited ${payload?['target_user_id'] ?? 'someone'} to a call';
      case RtmEvent.callAccept:
        return '${payload?['user_id'] ?? sender} accepted the call';
      case RtmEvent.callReject:
        return '${payload?['user_id'] ?? sender} rejected the call';
      case RtmEvent.presenceUpdate:
        return '$sender is now ${payload?['status'] ?? '?'} (${payload?['state'] ?? '?'})';
      case RtmEvent.pollVote:
        return '$sender voted ${payload?['option_id'] ?? '?'} on ${payload?['poll_id'] ?? 'a poll'}';
      default:
        return event.value;
    }
  }

  String _streamSuffix(Map<String, dynamic>? payload) {
    final streamId = payload?['stream_id'];
    return streamId == null ? '' : ' ($streamId)';
  }

  void _addSystemLine(String text) {
    if (!mounted) return;
    setState(() => _messages.add(_ChatMessage(id: _localId(), isMine: false, kind: _ChatKind.system, text: text)));
  }

  // ── Sending: text / rich / emoji ────────────────────────────────────

  void _sendMessage() {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty) return;

    final id = _rtm!.chat.send(_roomName, text);
    _myMessageIds.add(id);
    setState(() => _messages.add(_ChatMessage(id: id, isMine: true, kind: _ChatKind.text, text: text)));
    _messageCtrl.clear();
  }

  void _sendSticker() {
    final payload = {'type': 'sticker', 'id': 'party-parrot'};
    final id = _rtm!.chat.sendRichMessage(_roomName, payload);
    _myMessageIds.add(id);
    setState(() => _messages.add(_ChatMessage(id: id, isMine: true, kind: _ChatKind.rich, richPayload: payload)));
  }

  void _insertEmoji(String emoji) {
    final text = _messageCtrl.text;
    final selection = _messageCtrl.selection;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    _messageCtrl.text = text.replaceRange(start, end, emoji);
    _messageCtrl.selection = TextSelection.collapsed(offset: start + emoji.length);
  }

  void _notifyTyping() => _rtm?.chat.typingStart(_roomName);

  void _deleteMessage(_ChatMessage message) {
    if (!message.isMine) return;
    _rtm!.chat.deleteMessage(_roomName, message.id);
    setState(() => _messages.removeWhere((m) => m.id == message.id));
  }

  void _react(_ChatMessage message) {
    _rtm!.chat.reactionAdd(_roomName, message.id, '👍');
    setState(() => message.reaction = '👍');
  }

  // ── Sending / receiving files ────────────────────────────────────────

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    final path = result?.files.single.path;
    if (path == null) return;

    final file = File(path);
    final placeholder = _ChatMessage(
      id: _localId(),
      isMine: true,
      kind: _ChatKind.attachment,
      attachment: RtmAttachmentObject(
        fileId: '',
        name: file.uri.pathSegments.isEmpty ? 'file' : file.uri.pathSegments.last,
        size: 0,
        mimeType: 'application/octet-stream',
      ),
      uploadProgress: 0,
    );
    setState(() => _messages.add(placeholder));

    await for (final state in _session!.attachment.upload(file)) {
      switch (state) {
        case AttachmentLoading():
          break;
        case AttachmentProgress(:final progress):
          setState(() => placeholder.uploadProgress = progress);
        case AttachmentSuccess(:final data):
          final info = RtmAttachmentObject(
            fileId: data.attachmentId ?? placeholder.id,
            name: data.fileName ?? placeholder.attachment!.name,
            size: int.tryParse(data.fileSize ?? '') ?? 0,
            mimeType: data.mimeType ?? 'application/octet-stream',
          );
          _myAttachmentFileIds.add(info.fileId);
          setState(() {
            placeholder.uploadProgress = 100;
            placeholder.attachment = info;
          });
          // Bytes are already on the server via RoomSession.attachment - this
          // just tells the room about it so it renders as a bubble for
          // everyone else too.
          _rtm!.attachment.send([info]);
        case AttachmentError(:final message):
          setState(() => placeholder.uploadProgress = null);
          _addSystemLine('upload failed: $message');
      }
    }
  }

  Future<void> _downloadAttachment(_ChatMessage message) async {
    final info = message.attachment;
    final session = _session;
    if (info == null || session == null || info.fileId.isEmpty) return;

    setState(() => message.downloadProgress = 0);

    final dir = await getTemporaryDirectory();
    final destination = File('${dir.path}/${info.name}');

    await for (final state in session.attachment.download(info.fileId, destination)) {
      switch (state) {
        case AttachmentLoading():
          break;
        case AttachmentProgress(:final progress):
          setState(() => message.downloadProgress = progress);
        case AttachmentSuccess(:final data):
          setState(() {
            message.downloadProgress = 100;
            message.localFile = data;
          });
        case AttachmentError(:final error):
          setState(() => message.downloadProgress = null);
          _addSystemLine('download failed: $error');
      }
    }
  }

  // ── Secondary features (moderation / screen-share / call / presence) ──

  void _muteUser() {
    _rtm!.moderation.muteUser(_roomName, _targetUserCtrl.text.trim());
    _addSystemLine('you muted ${_targetUserCtrl.text}');
  }

  void _kickUser() {
    _rtm!.moderation.kickUser(_roomName, _targetUserCtrl.text.trim());
    _addSystemLine('you kicked ${_targetUserCtrl.text}');
  }

  void _startScreenShare() {
    _rtm!.screenShare.start(_roomName, _streamIdCtrl.text.trim());
    _addSystemLine('screen share start: ${_streamIdCtrl.text}');
  }

  void _stopScreenShare() {
    _rtm!.screenShare.stop(_roomName, _streamIdCtrl.text.trim());
    _addSystemLine('screen share stop: ${_streamIdCtrl.text}');
  }

  void _invite() {
    _rtm!.call.invite(_targetUserCtrl.text.trim(), _roomName);
    _addSystemLine('call invite -> ${_targetUserCtrl.text}');
  }

  void _accept() {
    _rtm!.call.accept(_roomName, _targetUserCtrl.text.trim(), _rtm!.identity ?? 'me');
    _addSystemLine('call accept <- ${_targetUserCtrl.text}');
  }

  void _reject() {
    _rtm!.call.reject(_roomName, _targetUserCtrl.text.trim(), _rtm!.identity ?? 'me');
    _addSystemLine('call reject <- ${_targetUserCtrl.text}');
  }

  void _updatePresence() {
    _rtm!.userAction.presence(_roomName, _statusCtrl.text.trim(), _stateCtrl.text.trim());
    _addSystemLine('presence: ${_statusCtrl.text}/${_stateCtrl.text}');
  }

  void _votePoll() {
    _rtm!.userAction.poll(_roomName, _pollIdCtrl.text.trim(), _optionIdCtrl.text.trim());
    _addSystemLine('voted ${_optionIdCtrl.text} on ${_pollIdCtrl.text}');
  }

  // ── UI ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      appBar: AppBar(
        title: Text(session == null ? 'RTM Chat Demo' : session.roomName),
        actions: session == null
            ? null
            : [
                IconButton(
                  tooltip: 'Features',
                  icon: const Icon(Icons.dashboard_customize_outlined),
                  onPressed: _openFeaturesSheet,
                ),
                IconButton(tooltip: 'Raw event log', icon: const Icon(Icons.terminal), onPressed: _openLogSheet),
                IconButton(tooltip: 'Leave', icon: const Icon(Icons.call_end), onPressed: _leave),
              ],
      ),
      body: session == null ? _buildJoinForm(context) : _buildChat(context),
    );
  }

  Widget _buildJoinForm(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
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
                : const Text('Join & connect RTM'),
          ),
        ],
      ),
    );
  }

  Widget _buildChat(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            reverse: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _messages.length,
            itemBuilder: (context, index) => _bubble(_messages[_messages.length - 1 - index]),
          ),
        ),
        if (_typingLabel != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(_typingLabel!, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            ),
          ),
        if (_showEmoji)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final emoji in _emojis)
                  IconButton(onPressed: () => _insertEmoji(emoji), icon: Text(emoji, style: const TextStyle(fontSize: 20))),
              ],
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Emoji',
                  icon: const Icon(Icons.emoji_emotions_outlined),
                  onPressed: () => setState(() => _showEmoji = !_showEmoji),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Attach',
                  icon: const Icon(Icons.add_circle_outline),
                  onSelected: (value) {
                    if (value == 'file') _pickAndSendFile();
                    if (value == 'sticker') _sendSticker();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'file', child: Text('Send file')),
                    PopupMenuItem(value: 'sticker', child: Text('Send sticker (rich message)')),
                  ],
                ),
                Expanded(
                  child: TextField(
                    controller: _messageCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Message',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _notifyTyping(),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(tooltip: 'Send', icon: const Icon(Icons.send), onPressed: _sendMessage),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _bubble(_ChatMessage m) {
    if (m.kind == _ChatKind.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 24),
        child: Center(
          child: Text(m.text ?? '', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        ),
      );
    }

    final theme = Theme.of(context);
    final bubbleColor = m.isMine ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest;

    return GestureDetector(
      onLongPress: () => _showMessageActions(m),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
        child: Row(
          mainAxisAlignment: m.isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.74),
              child: Column(
                crossAxisAlignment: m.isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!m.isMine)
                    Padding(
                      padding: const EdgeInsets.only(left: 10, bottom: 2),
                      child: Text(m.senderLabel, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: bubbleColor, borderRadius: BorderRadius.circular(14)),
                    child: _bubbleContent(m),
                  ),
                  if (m.reaction != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(m.reaction!, style: const TextStyle(fontSize: 14)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubbleContent(_ChatMessage m) {
    switch (m.kind) {
      case _ChatKind.text:
        return Text(m.text ?? '');
      case _ChatKind.rich:
        // The payload's `id`/`type` field only - never the raw map, even
        // for a rich message shape this example doesn't know about.
        final label = (m.richPayload?['id'] ?? m.richPayload?['type'])?.toString() ?? 'rich message';
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 6),
            Flexible(child: Text(label)),
          ],
        );
      case _ChatKind.attachment:
        return _attachmentContent(m);
      case _ChatKind.system:
        return const SizedBox.shrink();
    }
  }

  Widget _attachmentContent(_ChatMessage m) {
    final info = m.attachment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file, size: 20),
            const SizedBox(width: 6),
            Flexible(child: Text(info?.name ?? 'file', overflow: TextOverflow.ellipsis)),
          ],
        ),
        if (info != null && info.size > 0)
          Text('${info.size} bytes · ${info.mimeType}', style: const TextStyle(fontSize: 11)),
        if (m.uploadProgress != null && m.uploadProgress! < 100) ...[
          const SizedBox(height: 4),
          SizedBox(width: 160, child: LinearProgressIndicator(value: m.uploadProgress! / 100)),
          Text('Uploading ${m.uploadProgress}%', style: const TextStyle(fontSize: 11)),
        ],
        if (m.downloadProgress != null && m.downloadProgress! < 100) ...[
          const SizedBox(height: 4),
          SizedBox(width: 160, child: LinearProgressIndicator(value: m.downloadProgress! / 100)),
          Text('Downloading ${m.downloadProgress}%', style: const TextStyle(fontSize: 11)),
        ],
        if (!m.isMine && m.localFile == null && m.downloadProgress == null)
          TextButton.icon(
            onPressed: () => _downloadAttachment(m),
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Download'),
          ),
        if (m.localFile != null)
          Text('Saved: ${m.localFile!.path}', style: const TextStyle(fontSize: 11, color: Colors.green)),
      ],
    );
  }

  void _showMessageActions(_ChatMessage m) {
    if (m.kind == _ChatKind.system) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Text('👍', style: TextStyle(fontSize: 20)),
              title: const Text('React'),
              onTap: () {
                Navigator.pop(context);
                _react(m);
              },
            ),
            if (m.isMine)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete'),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessage(m);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _openLogSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        expand: false,
        builder: (context, scrollController) => Container(
          color: Colors.black87,
          padding: const EdgeInsets.all(12),
          child: ListView.builder(
            controller: scrollController,
            reverse: true,
            itemCount: _rawLog.length,
            itemBuilder: (context, index) => Text(
              _rawLog[_rawLog.length - 1 - index],
              style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
      ),
    );
  }

  void _openFeaturesSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.75,
          expand: false,
          builder: (context, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              Text('Features', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              _featureSection('Moderation', Icons.shield_outlined, [
                _labeledField('Target user id', _targetUserCtrl),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  OutlinedButton(onPressed: _muteUser, child: const Text('Mute user')),
                  OutlinedButton(onPressed: _kickUser, child: const Text('Kick user')),
                ]),
              ]),
              _featureSection('Screen-share signaling', Icons.screen_share_outlined, [
                _labeledField('Stream id', _streamIdCtrl),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  OutlinedButton(onPressed: _startScreenShare, child: const Text('Start')),
                  OutlinedButton(onPressed: _stopScreenShare, child: const Text('Stop')),
                ]),
              ]),
              _featureSection('Call invite', Icons.call_outlined, [
                Text('Uses the target user id above.', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  OutlinedButton(onPressed: _invite, child: const Text('Invite')),
                  OutlinedButton(onPressed: _accept, child: const Text('Accept')),
                  OutlinedButton(onPressed: _reject, child: const Text('Reject')),
                ]),
              ]),
              _featureSection('Presence & poll', Icons.people_outline, [
                Row(children: [
                  Expanded(child: _labeledField('Status', _statusCtrl)),
                  const SizedBox(width: 8),
                  Expanded(child: _labeledField('State', _stateCtrl)),
                ]),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _updatePresence, child: const Text('Update presence')),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _labeledField('Poll id', _pollIdCtrl)),
                  const SizedBox(width: 8),
                  Expanded(child: _labeledField('Option id', _optionIdCtrl)),
                ]),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _votePoll, child: const Text('Vote')),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _labeledField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
    );
  }

  Widget _featureSection(String title, IconData icon, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.w600))]),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}
