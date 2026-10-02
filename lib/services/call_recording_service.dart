import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class CallRecordingService {
  static const MethodChannel _channel = MethodChannel('talkstrangers/call_recording');

  static MediaRecorder? _activeVideoRecorder;
  static String? _activeVideoPath;
  static bool _audioRecordingActive = false;

  /// Retrieves an authoritative, unique output file path inside the app's cache directory.
  static Future<String?> getRecordingFilePath(String sessionId, {String ext = '.mp4'}) async {
    try {
      final res = await _channel.invokeMethod<String>('getRecordingFilePath', {
        'sessionId': sessionId,
        'ext': ext,
      });
      return res;
    } catch (e) {
      return null;
    }
  }

  /// Starts native audio recording to MPEG-4 / AAC.
  static Future<String?> startAudioRecording(String sessionId) async {
    try {
      final path = await _channel.invokeMethod<String>('startAudioRecording', {
        'sessionId': sessionId,
      });
      _audioRecordingActive = path != null;
      return path;
    } catch (e) {
      _audioRecordingActive = false;
      return null;
    }
  }

  /// Stops native audio recording and returns the path to the recorded file.
  static Future<String?> stopAudioRecording() async {
    if (!_audioRecordingActive) return null;
    try {
      final path = await _channel.invokeMethod<String>('stopAudioRecording');
      _audioRecordingActive = false;
      return path;
    } catch (e) {
      _audioRecordingActive = false;
      return null;
    }
  }

  /// Starts WebRTC native video recording using flutter_webrtc's MediaRecorder.
  static Future<String?> startVideoRecording(String sessionId, MediaStreamTrack videoTrack) async {
    try {
      final path = await getRecordingFilePath(sessionId, ext: '.mp4');
      if (path == null) return null;

      final recorder = MediaRecorder();
      await recorder.start(path, videoTrack: videoTrack);
      _activeVideoRecorder = recorder;
      _activeVideoPath = path;
      return path;
    } catch (e) {
      _activeVideoRecorder = null;
      _activeVideoPath = null;
      return null;
    }
  }

  /// Stops active video recording and returns the video file path.
  static Future<String?> stopVideoRecording() async {
    final recorder = _activeVideoRecorder;
    final path = _activeVideoPath;
    _activeVideoRecorder = null;
    _activeVideoPath = null;

    if (recorder != null) {
      try {
        await recorder.stop();
      } catch (_) {}
    }
    return path;
  }

  /// Master cleanup: stops both audio and video recorders and returns any valid recorded file.
  static Future<File?> stopAndCollectRecording() async {
    String? chosenPath;

    // 1. Try to finalize video recording
    final videoPath = await stopVideoRecording();
    if (videoPath != null) {
      final vFile = File(videoPath);
      if (await vFile.exists() && await vFile.length() > 1000) {
        chosenPath = videoPath;
      }
    }

    // 2. Try to finalize audio recording
    final audioPath = await stopAudioRecording();
    if (chosenPath == null && audioPath != null) {
      final aFile = File(audioPath);
      if (await aFile.exists() && await aFile.length() > 1000) {
        chosenPath = audioPath;
      }
    }

    if (chosenPath != null) {
      return File(chosenPath);
    }
    return null;
  }
}
