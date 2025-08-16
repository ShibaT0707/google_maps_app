import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

class SpeechService {
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;

  // Callback to notify the UI about recognized words
  void Function(String)? onResult;

  // Callback to notify the UI about status changes
  void Function(String)? onStatusChanged;

  Future<void> initialize({
    required void Function(String) onResult,
    required void Function(String) onStatusChanged,
  }) async {
    this.onResult = onResult;
    this.onStatusChanged = onStatusChanged;

    _speechEnabled = await _speechToText.initialize(
      onStatus: _onStatus,
      onError: (error) => print('Speech recognition error: $error'),
    );

    if (_speechEnabled) {
      _startListening();
    }
  }

  void _startListening() {
    if (!_speechEnabled) {
      print("The user has not granted speech recognition permission");
      return;
    }
    _speechToText.listen(
      onResult: _onSpeechResult,
      listenFor: const Duration(days: 1),
      pauseFor: const Duration(seconds: 5),
      partialResults: true,
      localeId: 'ja_JP', // Set locale to Japanese
    );
  }

  void _onStatus(String status) {
    if (onStatusChanged != null) {
      onStatusChanged!(status);
    }

    // When the status is 'done' or 'notListening', restart the listening session.
    if (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) {
      // Add a small delay before restarting to avoid rapid looping on some devices
      Future.delayed(const Duration(milliseconds: 500), () {
        _startListening();
      });
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (onResult != null) {
      onResult!(result.recognizedWords);
    }
  }

  void stopListening() {
    _speechToText.stop();
  }

  void cancelListening() {
    _speechToText.cancel();
  }
}
