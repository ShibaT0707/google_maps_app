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

    // The status listener is passed to initialize, not listen.
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
      partialResults: true, // Keep getting results
    );
  }

  void _onStatus(String status) {
    print('Speech recognition status: $status');
    // When the status is 'done' or 'notListening', it means the listening
    // session has ended for some reason (e.g., silence). Restart it.
    if (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) {
      if (onListeningStopped != null) {
        onListeningStopped!();
      }
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
