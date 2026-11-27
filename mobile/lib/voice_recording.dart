import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'api.dart';

class VoiceRecording {
  static const _maxBytes = 640000;
  final AudioRecorder _recorder;

  VoiceRecording({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();
  final _stop = Completer<void>();
  final _abort = Completer<void>();

  bool get isCancelled => _abort.isCompleted;

  void stop() {
    if (!_stop.isCompleted) _stop.complete();
  }

  void cancel() {
    if (!_abort.isCompleted) _abort.complete();
    stop();
  }

  Future<String?> listen(
    TrackerApi api, {
    required void Function() onRecording,
    required void Function() onTranscribing,
  }) async {
    final audio = BytesBuilder(copy: false);
    StreamSubscription<Uint8List>? subscription;
    Timer? limit;
    Object? recordingError;
    var streamClosed = false;
    try {
      if (_abort.isCompleted) return null;
      if (!await _recorder.hasPermission()) {
        throw const ApiException('Microphone permission is required.');
      }
      if (_abort.isCompleted) return null;
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      subscription = stream.listen(
        (chunk) {
          final remaining = _maxBytes - audio.length;
          if (remaining > 0) {
            audio.add(
              chunk.length <= remaining
                  ? chunk
                  : Uint8List.sublistView(chunk, 0, remaining),
            );
          }
          if (audio.length == _maxBytes) stop();
        },
        onError: (Object error) {
          recordingError = error;
          stop();
        },
        onDone: () {
          streamClosed = true;
          stop();
        },
      );
      if (!_stop.isCompleted) onRecording();
      limit = Timer(const Duration(seconds: 20), stop);
      await _stop.future;
      if (_abort.isCompleted) {
        await _recorder.cancel();
        return null;
      }
      onTranscribing();
      await _recorder.stop();
      if (recordingError != null) {
        throw const ApiException('Microphone recording was interrupted.');
      }
    } finally {
      limit?.cancel();
      if (!streamClosed) await subscription?.cancel();
      await _recorder.dispose();
    }
    if (_abort.isCompleted) return null;
    if (audio.isEmpty) return '';
    return api.transcribe(audio.takeBytes(), abortTrigger: _abort.future);
  }
}
