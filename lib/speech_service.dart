import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

class SpeechService {
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;

  // Callback to notify the UI about recognized words
  void Function(String)? onResult;

  // Callback to notify the UI when listening has stopped
  void Function()? onListeningStopped;

  Future<void> initialize({
    required void Function(String) onResult,
    required void Function() onListeningStopped,
  }) async {
    this.onResult = onResult;
    this.onListeningStopped = onListeningStopped;
    _speechEnabled = await _speechToText.initialize();
    _startListening();
  }

  void _startListening() {
    if (!_speechEnabled) {
      print("The user has not granted speech recognition permission");
      return;
    }
    _speechToText.listen(
      onResult: _onSpeechResult,
      listenFor: const Duration(days: 1), // Listen for a long time
      pauseFor: const Duration(seconds: 5), // Pause after 5s of silence
      onDone: () {
        // This is called when the listen session is finished.
        // We want to restart it to have continuous listening.
        _startListening();
        if (onListeningStopped != null) {
          onListeningStopped!();
        }
      },
    );
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (onResult != null) {
      onResult!(result.recognizedWords);
    }
  }

  void stopListening() {
    _speechToText.stop();
    if (onListeningStopped != null) {
      onListeningStopped!();
    }
  }

  void cancelListening() {
    _speechToText.cancel();
     if (onListeningStopped != null) {
      onListeningStopped!();
    }
  }
}
