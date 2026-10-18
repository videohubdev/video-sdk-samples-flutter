import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:videohub/videohub.dart';

import 'join_screen.dart';

// Fill these in with your own VideoHub project credentials before running -
// see the package README. Left as placeholders, join()/connect() will fail
// with an authentication error from the server.
const _apiKey = 'YOUR_API_KEY';
const _appId = 'YOUR_APP_ID';
const _appSecret = 'YOUR_APP_SECRET';
const appPlatform = 'web';
const appIdentifier = 'yourapp.com';
const appName = 'Your App';
const domain = 'yourapp.com';
const _username = 'you@example.com';
const _password = 'YOUR_PASSWORD';



void main() {
  WidgetsFlutterBinding.ensureInitialized();

  VideoHubSDK.create(
    const VideoHubConfig(
      apiKey: _apiKey,
      appId: _appId,
      appSecret: _appSecret,
      appPlatform: appPlatform,
      appIdentifier: appIdentifier,
      appName: appName,
      domain: domain,
      username: _username,
      password: _password,
      debug: true,
    ),
  );

  runApp(const GroupVideoChatApp());
}

class GroupVideoChatApp extends StatelessWidget {
  const GroupVideoChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'VideoHub Group Chat',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      debugShowCheckedModeBanner: false,
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const JoinScreen(),
    );
  }
}
