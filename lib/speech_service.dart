import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

class SpeechService {
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;

  // Callback to notify the UI about recognized words
  void Function(String)? onResult;

  // Callback to notify the UI about status changes
  void Function(String)? onStatusChanged;

  Future<bool> initialize({
    required void Function(String) onResult,
    required void Function(String) onStatusChanged,
  }) async {
    this.onResult = onResult;
    this.onStatusChanged = onStatusChanged;

    _speechEnabled = await _speechToText.initialize(
      onStatus: _onStatus,
      onError: (error) => print('Speech recognition error: $error'),
    );
    return _speechEnabled;
  }

  void listen({
    required String localeId,
    Duration? listenFor,
    Duration? pauseFor,
  }) {
    if (!_speechEnabled) {
      print("Speech service not initialized or permission denied.");
      return;
    }
    _speechToText.listen(
      onResult: _onSpeechResult,
      listenFor: listenFor,
      pauseFor: pauseFor,
      partialResults: true,
      localeId: localeId,
    );
  }

  void _onStatus(String status) {
    if (onStatusChanged != null) {
      onStatusChanged!(status);
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (onResult != null) {
      onResult!(result.recognizedWords);
    }
  }

  void stop() {
    _speechToText.stop();
  }

  void cancel() {
    _speechToText.cancel();
  }
}
