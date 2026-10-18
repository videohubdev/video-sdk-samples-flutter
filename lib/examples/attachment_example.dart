import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:videohub/videohub.dart';

/// Attachment upload/download, with progress - `RoomSession.attachment`.
///
/// Joins a room as a viewer (no mic/camera needed for this feature), then:
///  - `attachment.upload(file)` streams [AttachmentLoading] ->
///    zero-or-more [AttachmentProgress] (0-100) -> [AttachmentSuccess]/
///    [AttachmentError]. Files over 1 GB are rejected client-side before
///    any network call - see [maxAttachmentUploadBytes].
///  - `attachment.download(attachmentId, destination)` streams the same
///    shape in the other direction.
class AttachmentExample extends StatefulWidget {
  const AttachmentExample({super.key});

  @override
  State<AttachmentExample> createState() => _AttachmentExampleState();
}

class _AttachmentExampleState extends State<AttachmentExample> {
  final _roomCtrl = TextEditingController(text: 'attachment-demo');

  RoomSession? _session;
  bool _busy = false;
  String? _error;

  File? _pickedFile;
  int? _uploadProgress;
  UploadResponse? _uploaded;

  int? _downloadProgress;
  File? _downloadedFile;

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
      // Viewer join - attachments don't need a published mic/camera, just
      // an active room session to scope them to.
      final session = await VideoHubSDK.videoHub.join(_roomCtrl.text.trim());
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
    setState(() {
      _session = null;
      _pickedFile = null;
      _uploadProgress = null;
      _uploaded = null;
      _downloadProgress = null;
      _downloadedFile = null;
    });
  }

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    final path = result?.files.single.path;
    if (path == null) return;

    final session = _session;
    if (session == null) return;

    final file = File(path);
    setState(() {
      _pickedFile = file;
      _uploadProgress = null;
      _uploaded = null;
      _error = null;
      // A fresh upload invalidates whatever was downloaded before.
      _downloadProgress = null;
      _downloadedFile = null;
    });

    await for (final state in session.attachment.upload(file)) {
      switch (state) {
        case AttachmentLoading():
          setState(() => _uploadProgress = 0);
        case AttachmentProgress(:final progress):
          setState(() => _uploadProgress = progress);
        case AttachmentSuccess(:final data):
          setState(() {
            _uploadProgress = 100;
            _uploaded = data;
          });
        case AttachmentError(:final message):
          setState(() {
            _uploadProgress = null;
            _error = 'Upload failed: $message';
          });
      }
    }
  }

  Future<void> _download() async {
    final session = _session;
    final attachmentId = _uploaded?.attachmentId;
    if (session == null || attachmentId == null) return;

    final dir = await getTemporaryDirectory();
    final destination = File('${dir.path}/${_uploaded?.fileName ?? attachmentId}');

    setState(() {
      _downloadProgress = null;
      _downloadedFile = null;
      _error = null;
    });

    await for (final state in session.attachment.download(attachmentId, destination)) {
      switch (state) {
        case AttachmentLoading():
          setState(() => _downloadProgress = 0);
        case AttachmentProgress(:final progress):
          setState(() => _downloadProgress = progress);
        case AttachmentSuccess(:final data):
          setState(() {
            _downloadProgress = 100;
            _downloadedFile = data;
          });
        case AttachmentError(:final message):
          setState(() {
            _downloadProgress = null;
            _error = 'Download failed: $message';
          });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      appBar: AppBar(title: const Text('Attachment Example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: session == null ? _buildJoinForm(context) : _buildAttachmentUi(context, session),
      ),
    );
  }

  Widget _buildJoinForm(BuildContext context) {
    return Column(
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
              : const Text('Join room'),
        ),
      ],
    );
  }

  Widget _buildAttachmentUi(BuildContext context, RoomSession session) {
    return ListView(
      children: [
        Text('Room: ${session.roomName}', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        FilledButton.icon(
          onPressed: _pickAndUpload,
          icon: const Icon(Icons.upload_file),
          label: Text(_pickedFile == null ? 'Pick & upload a file' : 'Pick & upload another file'),
        ),
        if (_pickedFile != null) ...[
          const SizedBox(height: 12),
          Text('Selected: ${_pickedFile!.path.split('/').last}'),
          const SizedBox(height: 8),
          if (_uploadProgress != null) ...[
            LinearProgressIndicator(value: _uploadProgress! / 100),
            const SizedBox(height: 4),
            Text('Uploading: $_uploadProgress%'),
          ],
          if (_uploaded != null) ...[
            const SizedBox(height: 8),
            Text('Uploaded - attachment id: ${_uploaded!.attachmentId}'),
            Text('Size: ${_uploaded!.fileSize ?? '?'} bytes, type: ${_uploaded!.mimeType ?? '?'}'),
          ],
        ],
        if (_uploaded != null) ...[
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _download,
            icon: const Icon(Icons.download),
            label: const Text('Download it back'),
          ),
          if (_downloadProgress != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _downloadProgress! / 100),
            const SizedBox(height: 4),
            Text('Downloading: $_downloadProgress%'),
          ],
          if (_downloadedFile != null) ...[
            const SizedBox(height: 8),
            Text('Saved to: ${_downloadedFile!.path}'),
          ],
        ],
        const SizedBox(height: 24),
        OutlinedButton.icon(onPressed: _leave, icon: const Icon(Icons.call_end), label: const Text('Leave room')),
      ],
    );
  }
}
