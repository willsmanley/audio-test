import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

var apiToken = 'PASTE API TOKEN HERE';

void main() {
  runApp(const App());
}

class App extends StatefulWidget {
  const App({super.key});
  @override
  AppState createState() => AppState();
}

class AppState extends State<App> {
  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: MaterialApp(
        home: AudioTest(),
      ),
    );
  }
  
}

class AudioTest extends StatefulWidget {
  const AudioTest({super.key});
  @override
  State<AudioTest> createState() => AudioTestState();
}

class AudioTestState extends State<AudioTest> {
  late AudioPlayer _audioPlayer;
  late WebSocketChannel _channel;
    late StreamController<List<int>> _audioBuffer;

  @override
  void initState() {
    super.initState();
    _audioBuffer = StreamController<List<int>>();
    _registerCall();
    _registerPlayer();
  }

  Future<void> _registerPlayer() async {
    _audioPlayer = AudioPlayer();
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
  }

  Future<void> _registerCall() async {
    final response = await http.get(
      Uri.parse('https://safe-gorge-65703-197182a5b4e2.herokuapp.com/call-id'),
      headers: {
        'X-API-TOKEN': apiToken,
        'Content-Type': 'application/json',
      },
    );
    var callId = response.body.replaceAll(RegExp(r'^"|"$'), '');
    print('call id: $callId');
    _initializeWebsocketChannel(callId);
  }

  void _initializeWebsocketChannel(String callId) {
    _channel = WebSocketChannel.connect(
        Uri.parse('wss://api.retellai.com/audio-websocket/$callId'));
    print('websocket channel initialized');

    _channel.stream.listen((data) {
      if (data is List<int>) {
        print('Received audio data: $data');
        _audioBuffer.add(data);
        if (!_audioPlayer.playing) {
          _playStream();
        }
      }
    });
  }

  Future<void> _playStream() async {
    try {
      final source = ByteStreamAudioSource(_audioBuffer.stream);
      print('Setting audio source...');
      await _audioPlayer.setAudioSource(source);
      print('Audio source set');

      print('Starting playback...');
      await _audioPlayer.play();
      print('Playback started');
    } catch (e) {
      print('Error in playing stream: $e');
    }
  }

  @override
  void dispose() {
    _channel.sink.close();
    _audioPlayer.dispose();
    _audioBuffer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Test'),
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [],
        ),
      ),
    );
  }
}

class ByteStreamAudioSource extends StreamAudioSource {
  final Stream<List<int>> _byteStream;

  ByteStreamAudioSource(this._byteStream);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    print('Requesting audio stream...');
    return StreamAudioResponse(
      sourceLength: null,
      offset: 0,
      contentLength: null,
      contentType: 'audio/pcm',
      stream: _byteStream,
    );
  }
}
