import 'package:flutter/material.dart';
import 'package:videohub/videohub.dart';

/// Minimal participant tile shared by the feature examples in this
/// directory - renders whatever video track is published (or a placeholder
/// if none) plus a mic-state badge. Not part of the SDK; just UI plumbing
/// so each example file can stay focused on the SDK call it demonstrates.
class SimpleParticipantTile extends StatelessWidget {
  const SimpleParticipantTile({required this.participant, required this.label, required this.isLocal, super.key});

  final BaseParticipant participant;
  final String label;
  final bool isLocal;

  @override
  Widget build(BuildContext context) {
    // The participant's ChangeNotifier already covers track publish/mute
    // changes, so listening here keeps the tile in sync without a
    // dedicated stream per field.
    return AnimatedBuilder(
      animation: participant.participant,
      builder: (context, _) {
        final track = participant.preferredVideoTrack();

        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
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
                  const Center(child: Icon(Icons.person, color: Colors.white54, size: 40)),
                Positioned(
                  left: 6,
                  bottom: 6,
                  right: 6,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        participant.isMicrophoneEnabled ? Icons.mic : Icons.mic_off,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          label,
                          style: const TextStyle(color: Colors.white, fontSize: 11),
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
