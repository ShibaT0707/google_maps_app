# Picovoice Flutter Demo: Wake Word and Streaming Transcription

This Flutter application demonstrates how to use Picovoice to create a voice-activated experience. It integrates the Porcupine wake word engine and the Cheetah streaming speech-to-text engine.

The app listens for the wake word "blueberry". When detected, it starts transcribing the user's speech in real-time until they pause. The transcribed text is displayed on the screen. This functionality is integrated into a Google Maps screen.

## Requirements

- Flutter 2.8.1+
- Android 5.0+ (API 21+) or iOS 13.0+
- A Picovoice AccessKey
- A microphone

## Setup

### 1. Get your Picovoice AccessKey

The Picovoice SDKs require a valid `AccessKey` for initialization. You can get a free one from the [Picovoice Console](https://console.picovoice.ai/).

Once you have your key, open `lib/main.dart` and replace the placeholder value:

```dart
// lib/main.dart
const String accessKey = "YOUR_PICOVOICE_ACCESS_KEY_HERE";
```

### 2. Get the Model and Keyword Files

This application requires three files to be placed in the `assets` directory:

- **Porcupine Model File (`.pv`)**: The base model for the Porcupine engine.
- **Porcupine Keyword File (`.ppn`)**: The model for the "blueberry" wake word.
- **Cheetah Model File (`.pv`)**: The base model for the Cheetah engine.

**Steps to get the files:**

1.  **Download the default model files:**
    - Go to the [Porcupine GitHub repository](https://github.com/Picovoice/porcupine/tree/master/lib/common) and download `porcupine_params.pv`.
    - Go to the [Cheetah GitHub repository](https://github.com/Picovoice/cheetah/tree/master/lib/common) and download `cheetah_params.pv`.

2.  **Download the "blueberry" keyword file:**
    - The keyword files are platform-specific. Go to the [Porcupine GitHub repository](https://github.com/Picovoice/porcupine/tree/master/resources/keyword_files) and download the file for your target platform (e.g., `blueberry_android.ppn` for Android, `blueberry_ios.ppn` for iOS).
    - **Note:** For this demo, you can start with one platform (e.g., Android) and rename the file if you switch. For a production app, you would need to handle platform-specific asset loading.

3.  **Place the files in the `assets` directory:**
    - Create an `assets` folder in the root of your Flutter project if it doesn't exist.
    - Place the three downloaded files into this folder.

4.  **Update the paths in `lib/main.dart` (if necessary):**
    - The code expects the files to be named as follows. If you downloaded a different keyword file (e.g., for iOS), make sure to update the `keywordPath` constant in `lib/main.dart`.

    ```dart
    // lib/main.dart
    const String porcupineModelPath = "assets/porcupine_params.pv";
    const String keywordPath = "assets/blueberry_android.ppn"; // Change if using a different platform
    const String cheetahModelPath = "assets/cheetah_params.pv";
    ```

### 3. Install Dependencies

The necessary dependencies are already listed in `pubspec.yaml`. Flutter should automatically install them when you run the app. If not, you can run:

```bash
flutter pub get
```

## Running the App

1.  Connect a device or start an emulator/simulator.
2.  Run the app from your IDE or using the command line:

    ```bash
    flutter run
    ```

3.  Once the app is running, press the microphone button. It will turn red, and the app will start listening for the wake word "blueberry".
4.  Say "blueberry". The status message will change, and the app will start transcribing your speech.
5.  When you stop talking, the transcription will end, and the app will go back to listening for the wake word.
6.  Press the microphone button again to stop the Picovoice engines.

## Note on Permissions

The app will request microphone permissions on the first run. You must grant permission for the voice recognition to work. The necessary permission declarations are already included in `AndroidManifest.xml` and `Info.plist`.
