import 'package:flutter/material.dart';

import 'call_join_screen.dart';
import 'examples/attachment_example.dart';
import 'examples/audio_only_example.dart';
import 'examples/audio_video_example.dart';
import 'examples/multi_room_example.dart';
import 'examples/rtm_example.dart';
import 'examples/video_only_example.dart';
import 'sdk_demo_screen.dart';

/// One feature, one example - each entry below is a self-contained screen
/// demonstrating a single VideoHub SDK capability in isolation. See the
/// package README for the accompanying write-up of each one.
class ExamplesMenuScreen extends StatelessWidget {
  const ExamplesMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Feature Examples')),
      body: ListView(
        children: [
          _entry(
            context,
            icon: Icons.videocam,
            title: 'Video only',
            subtitle: 'join(audio: false, video: true) - camera, no mic',
            screen: const VideoOnlyExample(),
          ),
          _entry(
            context,
            icon: Icons.mic,
            title: 'Audio only',
            subtitle: 'join(audio: true, video: false) - group voice call',
            screen: const AudioOnlyExample(),
          ),
          _entry(
            context,
            icon: Icons.duo,
            title: 'Audio + video',
            subtitle: 'join(audio: true, video: true) - both tracks',
            screen: const AudioVideoExample(),
          ),
          _entry(
            context,
            icon: Icons.call,
            title: '1:1 call',
            subtitle: 'Call.start/join/end + mute/kick/video-off moderation',
            screen: const CallJoinScreen(),
          ),
          _entry(
            context,
            icon: Icons.grid_view,
            title: 'Multi-room join',
            subtitle: 'Two independent RoomSessions live at once',
            screen: const MultiRoomExample(),
          ),
          _entry(
            context,
            icon: Icons.attach_file,
            title: 'Attachments',
            subtitle: 'attachment.upload/download with progress, 1 GB cap',
            screen: const AttachmentExample(),
          ),
          _entry(
            context,
            icon: Icons.forum,
            title: 'RTM chat',
            subtitle: 'Full chat UI - files, stickers, emoji, moderation, call invite, presence/poll',
            screen: const RtmExample(),
          ),
          _entry(
            context,
            icon: Icons.terminal,
            title: 'SDK primitives',
            subtitle: 'join/connect/publish/unpublish, one button per call',
            screen: const SdkDemoScreen(),
          ),
        ],
      ),
    );
  }

  Widget _entry(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget screen,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => screen)),
    );
  }
}
