# video-sdk-samples-flutter

VideoHub Flutter SDK Example  — Group Video chat, group audio chat, 1:1 call, RTM chat,
screen share

## Install

```yaml
dependencies:
  videohub_flutter:
    videohub: ^0.3.0 
```

## Setup

Initialize the SDK once, e.g. in `main()`:

```dart
import 'package:videohub_flutter/videohub_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  VideoHubSDK.create(
    const VideoHubConfig(
      apiKey: 'vhub_hub_...',
      appId: '...',
      appSecret: '...',
      appIdentifier: 'yourapp.com',
      appName: 'Your App',
      domain: 'yourapp.com',
      username: 'you@example.com',
      password: '...',
      debug: true, // logs every REST call and its response
    ),
  );

  runApp(const MyApp());
}
```

From anywhere after that, reach the SDK via `VideoHubSDK.videoHub`.

## Group rooms

### Join as host

`join` creates the room on the server, obtains a host token, and connects.
`audio`/`video` control what publishes immediately — see
[Audio-only / video-only / viewer-only](#audio-only--video-only--viewer-only)
below for every combination.

```dart
final session = await VideoHubSDK.videoHub.join(
  'my-room',
  audio: true,
  video: true,
);
```

### Join as guest

`connect` obtains a subscribe-only token — a guest can watch/listen but
never publish, even later:

```dart
final session = await VideoHubSDK.videoHub.connect('my-room');
```

### Rendering participants

`RoomSession.local`/`.remote` expose the participants; `preferredVideoTrack()`
picks whatever's published (screen share over camera), and each
participant's own `ChangeNotifier` drives the widget:

```dart
AnimatedBuilder(
  animation: session.local.participant,
  builder: (context, _) {
    final track = session.local.preferredVideoTrack();
    return track != null
        ? VideoTrackRenderer(track, mirrorMode: VideoViewMirrorMode.mirror)
        : const Icon(Icons.person);
  },
)
```

Remote roster changes come through `session.room` (also a `ChangeNotifier`):

```dart
AnimatedBuilder(
  animation: session.room,
  builder: (context, _) => Column(
    children: [
      for (final p in session.remote.participants.values)
        Text(session.remote.moderation(p).identity),
    ],
  ),
)
```

### Leaving

```dart
VideoHubSDK.videoHub.leaveRoom('my-room'); // or session.roomName
```

If you joined as **host**, `leaveRoom` also deletes the room server-side
afterward (best-effort, logged only when `debug: true`) — a group room is
the host's to tear down, so guests aren't left stranded in a room nobody
can host again. A **guest** (`connect`) leaving only disconnects; the room
is left for its host to close. `leaveAllRooms()` applies the same rule to
every joined room.

## Audio-only / video-only / viewer-only

`audio`/`video` on `join` are independent, so a call can be exactly what it
needs to be:

```dart
// Group voice call - camera never requested or published.
await VideoHubSDK.videoHub.join('room', audio: true, video: false);

// Silent video feed - microphone never requested or published.
await VideoHubSDK.videoHub.join('room', audio: false, video: true);

// Pure viewer - publishes nothing, but (unlike connect()) still holds
// publish rights and can start a stream later.
await VideoHubSDK.videoHub.join('room'); // audio/video default to false
```

Full runnable versions: [`examples/audio_only_example.dart`](example/lib/examples/audio_only_example.dart),
[`examples/video_only_example.dart`](example/lib/examples/video_only_example.dart).

### Publish / unpublish on demand

Once joined, `RoomSession.local` can start or stop any track
independently at any time — the mechanism a viewer uses to become a
publisher, or a publisher uses to drop back to viewing:

```dart
// Start contributing audio and/or video:
await session.local.publish(audio: true);
await session.local.publish(video: true);
await session.local.publish(audio: true, video: true);

// Stop, independently or together:
await session.local.unpublish(audio: true);
await session.local.unpublish(video: true);
await session.local.unpublishAll(); // back to a pure viewer
```

`setMicrophoneEnabled`/`setCameraEnabled` remain available too — `publish`/
`unpublish` are just the audio/video/screen-aware convenience layer on top
(see below for the `screen:` argument).

## Screen share

`RoomSession.local` publishes/unpublishes a screen-share track the same way
it does mic/camera — `publish`/`unpublish` take a `screen:` argument too:

```dart
// Start sharing (triggers the platform's screen-capture picker):
await session.local.setScreenShareEnabled(true);
// ...or, alongside other tracks in one call:
await session.local.publish(audio: true, screen: true);

// Stop sharing:
await session.local.setScreenShareEnabled(false);
// ...or:
await session.local.unpublish(screen: true);

session.local.isScreenShareEnabled; // works on any participant, not just local
```

`isScreenShareEnabled` is on `BaseParticipant`, so it also tells you whether
a *remote* participant is sharing: `session.remote.moderation(p).isScreenShareEnabled`.

### Android setup (required)

Android 14+ throws `SecurityException: Media projections require a
foreground service of type ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION`
unless a foreground service of that type is already running before
`setScreenShareEnabled(true)` is called, don't start this service on the
app's behalf, so every app using screen share on Android needs to:

1. Add the [`flutter_background`](https://pub.dev/packages/flutter_background) package.
2. Declare its service in `AndroidManifest.xml`, with the `mediaProjection` type:
   ```xml
   <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
   <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION" />
   <application>
     ...
     <service
         android:name="de.julianassmann.flutter_background.IsolateHolderService"
         android:enabled="true"
         android:exported="false"
         android:foregroundServiceType="mediaProjection" />
   </application>
   ```
3. Before calling `local.setScreenShareEnabled(true)` on Android, request
   capture permission via `local.requestScreenCapturePermission()` and
   start the foreground service via `FlutterBackground.enableBackgroundExecution()`;
   stop it again once sharing ends.

Full runnable version of that sequence:
[`android_screen_share.dart`](example/lib/android_screen_share.dart) (used by
[`RoomController.dart`](example/lib/RoomController.dart) and
[`CallController.dart`](example/lib/CallController.dart)). iOS/macOS/web/desktop
need no equivalent setup.

### Rendering the screen-share track

`preferredVideoTrack()` picks screen share over camera automatically when
both are live — fine for a single-tile layout. For a UI that renders both
at once (screen share as the main view, camera as a small overlay, or
side-by-side), use the explicit accessors instead:

```dart
participant.cameraTrack;       // the camera track specifically, or null
participant.screenShareTrack;  // the screen-share track specifically, or null
```

```dart
// Screen content should never be cropped, unlike a camera feed - use
// VideoViewFit.contain rather than the default cover fit:
VideoTrackRenderer(participant.screenShareTrack!, fit: VideoViewFit.contain)
```

Full runnable version, rendering camera and screen share as separate tiles
with independent toggle buttons: [`room_screen.dart`](example/lib/room_screen.dart) /
[`RoomController.dart`](example/lib/RoomController.dart).

## Multi-room join

Rooms are peers, not a single "active room" — joining a second room never
disconnects the first. Each `join`/`connect` call returns its own
independent `RoomSession`, and they're all tracked in `VideoHub.sessions`:

```dart
final roomA = await VideoHubSDK.videoHub.join('room-a', audio: true, video: true);
final roomB = await VideoHubSDK.videoHub.connect('room-b'); // guest, concurrently

VideoHubSDK.videoHub.leaveRoom('room-b'); // room-a stays live

VideoHubSDK.videoHub.sessions; // Map<String, RoomSession> - every joined room
VideoHubSDK.videoHub.observeAllEvents(); // merged event stream, tagged by room name
```

Full runnable version, joining two independent rooms side by side:
[`examples/multi_room_example.dart`](example/lib/examples/multi_room_example.dart).

## Attachments

`RoomSession.attachment` uploads/downloads files scoped to a room, each as
a `Stream<AttachmentState<T>>`: exactly one [`AttachmentLoading`], zero or
more [`AttachmentProgress`] (0-100), then exactly one of
[`AttachmentSuccess`]/[`AttachmentError`] - after which the stream closes.
Mirrors the Android SDK's `Attachment`/`AttachmentState`.

```dart
await for (final state in session.attachment.upload(file)) {
  switch (state) {
    case AttachmentLoading():
      print('starting…');
    case AttachmentProgress(:final progress):
      print('$progress%');
    case AttachmentSuccess(:final data):
      print('done - attachment id: ${data.attachmentId}');
    case AttachmentError(:final message):
      print('failed: $message');
  }
}
```

```dart
final destination = File('${(await getTemporaryDirectory()).path}/myfile.pdf');

await for (final state in session.attachment.download(attachmentId, destination)) {
  // same AttachmentState<File> shape as upload
}
```

Files over 1 GB (`maxAttachmentUploadBytes`) are rejected with
`AttachmentError` before any network call - the same client-side cap the
Android SDK enforces. Both directions stream to/from disk rather than
buffering the whole file in memory, so this scales to large files without
an `OutOfMemoryError`-equivalent risk.

Full runnable version: [`examples/attachment_example.dart`](example/lib/examples/attachment_example.dart).

## 1:1 calls

`VideoHub.call` is peer-to-peer calling built on the same `RoomSession`
primitives above, with its own REST lifecycle (`start`/`join`/`end`) and
moderation scoped to "the other participant" rather than a roster.

```dart
final call = VideoHubSDK.videoHub.call;

// Caller:
final session = await call.start(
  'caller_1',
  'callee_1',
  audio: true,
  video: true,
  onCallCreated: (callId, roomName) {
    // Fires before the RTC connection is up - show a ringing UI, notify
    // the callee, etc.
  },
);

// Callee, once they have callId (e.g. via push notification):
final session = await call.join(callId, audio: true, video: true);

// Moderating the other participant:
await call.mute(true);       // mute them
await call.videoOff(true);   // disable their camera
await call.kick();           // remove them from the call

// Ending the call server-side, then leaving the local session:
await call.end();
VideoHubSDK.videoHub.leaveRoom(session.roomName);
```

Full runnable version: [`CallJoinController.dart`](example/lib/CallJoinController.dart) /
[`call_join_screen.dart`](example/lib/call_join_screen.dart) (start/join) and
[`CallController.dart`](example/lib/CallController.dart) / [`call_screen.dart`](example/lib/call_screen.dart)
(in-call UI + moderation).

## RTM (real-time messaging/signaling)

`RoomSession.bindRtm()` opens a second, independent WebSocket channel per
room - chat, typing/raise-hand, moderation signaling, screen-share
signaling, call invites, and presence/poll, all multiplexed as
`{"event": ..., "payload": ...}` frames. Mirrors the Android SDK's
`RTM`/`EVENT`.

```dart
final session = await VideoHubSDK.videoHub.join('room');

// Best-effort by design - failures are caught and only logged (with
// debug: true), not thrown. Check rtm/isConnected if you need to know.
await session.bindRtm();
final rtm = session.rtm;
if (rtm == null || !rtm.isConnected) {
  // RTM didn't connect - the room itself is still fine.
}
```

### Sending

Each sub-namespace is a typed convenience over `rtm.send`:

```dart
rtm!.chat.send(session.roomName, 'hello');
rtm.chat.typingStart(session.roomName);
rtm.chat.raiseHand(session.roomName, true);

rtm.moderation.muteUser(session.roomName, targetUserId);
rtm.moderation.kickUser(session.roomName, targetUserId);

rtm.screenShare.start(session.roomName, streamId);
rtm.screenShare.stop(session.roomName, streamId);

rtm.call.invite(targetUserId, session.roomName);

rtm.userAction.presence(session.roomName, 'online', 'active');
rtm.userAction.poll(session.roomName, pollId, optionId);
```

For anything without a typed wrapper, send
directly - `RtmPayloads` has a builder for every [`RtmEvent`]:

```dart
rtm.send(RtmEvent.signalOffer, RtmPayloads.signalOffer(roomId, targetUserId, sdp));
```

### Receiving

`on`/`off` are a plain synchronous event emitter (not a `Stream`) - always
pair `on` with `off` using the same callback instance:

```dart
void onChatMessage(Map<String, dynamic>? payload) {
  print(payload?['message']);
}

rtm.on(RtmEvent.chatMessage, onChatMessage);
// ...later:
rtm.off(RtmEvent.chatMessage, onChatMessage);

// Or every event, regardless of type:
rtm.on(RtmEvent.all, (payload) => print(payload));
```

### Cleanup

`releaseRtm()` disconnects just the RTM channel (the RTC room keeps
running); `release()` (called by `VideoHub.leaveRoom`) calls it too, so
this is only needed if you want to drop signaling while staying in the
room.

Full runnable version: [`examples/rtm_example.dart`](example/lib/examples/rtm_example.dart) - a real
chat screen (left/right bubbles, sender label, timestamps), with file
send/receive (`RoomSession.attachment` for the bytes + `Rtm.attachment` to
announce it), sticker/rich messages, an emoji picker, typing indicator,
reactions, message delete, and every other sub-namespace (moderation,
screen-share signaling, call invite, presence/poll) reachable from the
toolbar's Features sheet, plus a raw log of every incoming frame.

## Room state & events

```dart
session.sessionState;      // RoomSessionState.connected, .reconnecting, ...
session.observeState();    // Stream<RoomSessionState>, replays latest value
session.observeEvents();   // Stream<VideoHubEvent> - connect/disconnect/tracks/etc.
```

## Moderating other participants (group rooms)

```dart
final item = session.remote.moderation(participant);
await item.kick(item.identity);
await item.mute(item.identity);
```

## Example app

Run app and tap **Browse feature examples** from the home screen, or
jump straight to a file:

| Feature | Example |
| --- | --- |
| Video only | [`examples/video_only_example.dart`](example/lib/examples/video_only_example.dart) |
| Audio only | [`examples/audio_only_example.dart`](example/lib/examples/audio_only_example.dart) |
| Audio + video | [`examples/audio_video_example.dart`](example/lib/examples/audio_video_example.dart) |
| Screen share / unshare | [`room_screen.dart`](example/lib/room_screen.dart) + [`RoomController.dart`](example/lib/RoomController.dart) |
| 1:1 call | [`call_join_screen.dart`](example/lib/call_join_screen.dart) + [`call_screen.dart`](example/lib/call_screen.dart) |
| Multi-room join | [`examples/multi_room_example.dart`](example/lib/examples/multi_room_example.dart) |
| Attachments (upload/download with progress) | [`examples/attachment_example.dart`](example/lib/examples/attachment_example.dart) |
| RTM chat (files, stickers, emoji, moderation, call invite, presence/poll) | [`examples/rtm_example.dart`](example/lib/examples/rtm_example.dart) |
| SDK primitives (join/connect/publish/unpublish, one button per call) | [`sdk_demo_screen.dart`](example/lib/sdk_demo_screen.dart) |
| Full group-chat UI (GetX) | [`join_screen.dart`](example/lib/join_screen.dart) + [`room_screen.dart`](example/lib/room_screen.dart) |
