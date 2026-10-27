// Demo entrypoint: a reply streaming into a chat row.
//   fvm flutter run -t lib/streaming_main.dart
import 'package:chat_scroll_view_example/src/features/streaming/streaming_screen.dart';
import 'package:flutter/material.dart';

void main() => runApp(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(),
    home: const StreamingScreen(),
  ),
);
