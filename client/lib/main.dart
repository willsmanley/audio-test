import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_sound/flutter_sound.dart';
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';

//------------------------------------------------------
//------------------------------------------------------
var apiToken = 'ADD API TOKEN HERE!!!';
//------------------------------------------------------
//------------------------------------------------------

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

// TODO: consider how other audio interrupts will be handled via https://pub.dev/packages/audio_session
class AudioTest extends StatefulWidget {
  const AudioTest({super.key});
  @override
  State<AudioTest> createState() => AudioTestState();
}

class AudioTestState extends State<AudioTest> {
  late WebSocketChannel _channel;
  final FlutterSoundRecorder _recorder =
      FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  late StreamController<Food> _audioStreamController;
  bool _isRecording = false;
  bool _recorderInitialized = false;
  bool _playerInitialized = false;

  @override
  void initState() {
    super.initState();
    _registerCall();
    _audioStreamController = StreamController<Food>();
  }

  Future<void> _initializeAudio() async {
    print('initializing player');
    await _player.openPlayer();
    setState(() {
      _playerInitialized = true;
    });
    print('player initialized');

    print('requesting microphone permission');
    var status = await Permission.microphone.request();
    print('status');
    print(status);
    if (status != PermissionStatus.granted) {
      print('permission not granted');
      throw RecordingPermissionException('Microphone permission not granted');
    }
    print('permission granted');
    await _recorder.openRecorder();
    print('recorder opened');
    _recorderInitialized = true;
  }

  Future<void> _registerCall() async {
    final response = await http.get(
      Uri.parse('https://powerful-hamlet-06075-3a5b6fc81641.herokuapp.com/call-id'),
      headers: {
        'X-API-TOKEN': apiToken,
        'Content-Type': 'application/json',
      },
    );
    print('call id: ${response.body}');
    _initializeWebsocketChannel(response.body);
  }

  void _initializeWebsocketChannel(String callId) {
    print('initializing websocket channel');
    _channel = WebSocketChannel.connect(
        Uri.parse('wss://api.retellai.com/audio-websocket/$callId'));
    print('channel initialized');
    _channel.stream.listen((data) async {
      print('listening');
      if (data is List<int>) {
        print('has data');
        _playRawAudio(Uint8List.fromList(data));
      } else if (data == 'clear') {
        print('clearing');
        _player.stopPlayer();
      }
    });
    _initializeAudio();
  }

  Future<void> _startRecording() async {
    print('starting recording');
    print(_isRecording);
    print(_recorderInitialized);
    if (_isRecording || !_recorderInitialized) return;
    print('continuing');
    // Ensure the player is stopped
    if (_player.isPlaying) {
      print('stopping player');
      await _player.stopPlayer();
    }

    setState(() {
      _isRecording = true;
    });

    print('really starting recording');
    await _recorder.startRecorder(
      toStream: _audioStreamController.sink,
      codec: Codec.pcm16,
      sampleRate: 24000,
      numChannels: 1,
    );
    print('recorder started');
    // Listen to the stream and send bytes to the WebSocket
    _audioStreamController.stream.listen((food) {
      print('food');
      if (food is FoodData) {
        print('is food');
        _channel.sink.add(food.data);
      }
    });
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    await _recorder.stopRecorder();
    setState(() {
      _isRecording = false;
    });
    await _audioStreamController.close();
  }

  Future<void> _playRawAudio(Uint8List audioBytes) async {
    if (!_playerInitialized) return;
    await _player.startPlayer(
      fromDataBuffer: audioBytes,
      codec: Codec.pcm16,
      sampleRate: 24000,
      numChannels: 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Test'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _isRecording ? _stopRecording : _startRecording,
              child: Text(_isRecording ? 'Stop Recording' : 'Start Recording'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _channel.sink.close();
    if (_recorderInitialized) {
      _recorder.closeRecorder();
    }
    if (_playerInitialized) {
      _player.closePlayer();
    }
    _audioStreamController.close();
    super.dispose();
  }
}
