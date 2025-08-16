import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:porcupine_flutter/porcupine_manager.dart';
import 'package:porcupine_flutter/porcupine_error.dart';
import 'package:cheetah_flutter/cheetah_manager.dart';
import 'package:cheetah_flutter/cheetah_error.dart';

// --- Picovoice Configuration ---
// TODO: Replace with your Picovoice AccessKey
const String accessKey = "YOUR_PICOVOICE_ACCESS_KEY_HERE";
// TODO: Add your custom model files to the assets folder and update the paths.
// You can get the default models from the Picovoice GitHub or create your own in the Picovoice Console.
const String porcupineModelPath = "assets/porcupine_params.pv";
const String keywordPath = "assets/blueberry_android.ppn"; // Using a placeholder path
const String cheetahModelPath = "assets/cheetah_params.pv";


void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  final Set<Marker> _markers = {};

  // --- Picovoice State Variables ---
  bool _isListening = false;
  String _statusMessage = "Press the mic button to start listening.";
  String _transcript = "";

  static const _ritzCarltonSFO = LatLng(37.788302, -122.403209);

  static const _initialCameraPosition = CameraPosition(
    target: _ritzCarltonSFO,
    zoom: 14.0,
  );

  @override
  void initState() {
    super.initState();
    _setInitialState();
  }

  // Using low-level APIs
  Porcupine? _porcupine;
  Cheetah? _cheetah;
  StreamSubscription? _voiceProcessorSubscription;
  bool _isTranscribing = false;

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  Future<void> _initPicovoice() async {
    if (accessKey == "YOUR_PICOVOICE_ACCESS_KEY_HERE") {
      setState(() {
        _statusMessage = "Please add your Picovoice AccessKey.";
      });
      return;
    }

    try {
      _porcupine = await Porcupine.fromKeywordPaths(
        accessKey,
        [keywordPath],
        _wakeWordCallback,
        modelPath: porcupineModelPath,
      );
      _cheetah = await Cheetah.create(
        accessKey,
        cheetahModelPath,
        endpointDurationSec: 1.0,
        enableAutomaticPunctuation: true,
      );
      setState(() {
        _statusMessage = "Picovoice initialized.";
      });
    } on PicovoiceException catch (e) {
      _errorCallback(e);
    }
  }

  void _wakeWordCallback(int keywordIndex) {
    if (keywordIndex == 0) { // blueberry
      setState(() {
        _isTranscribing = true;
        _statusMessage = "Wake word detected, listening for speech...";
      });
    }
  }

  void _errorCallback(PicovoiceException error) {
    setState(() {
      _statusMessage = error.message!;
    });
  }

  Future<void> _toggleListening() async {
    if (_voiceProcessorSubscription != null) {
      await _stopListening();
    } else {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    if (_porcupine == null || _cheetah == null) {
      await _initPicovoice();
    }
    if (_porcupine == null || _cheetah == null) {
      return; // Init failed
    }

    final voiceProcessor = VoiceProcessor.instance;
    _voiceProcessorSubscription = voiceProcessor.addFrameListener((frame) async {
      if (_isTranscribing) {
        try {
          final result = await _cheetah!.process(frame);
          if (result != null) {
            setState(() {
              _transcript += result.transcript;
              if (result.isEndpoint) {
                _transcript += " ";
                _isTranscribing = false;
                _statusMessage = "Finished transcribing. Listening for 'blueberry'...";
              }
            });
          }
        } on CheetahException catch (e) {
          _errorCallback(e);
        }
      } else {
        try {
          final keywordIndex = await _porcupine!.process(frame);
          if (keywordIndex >= 0) {
            _wakeWordCallback(keywordIndex);
          }
        } on PorcupineException catch (e) {
          _errorCallback(e);
        }
      }
    });

    try {
      await voiceProcessor.start(_porcupine!.frameLength, _porcupine!.sampleRate);
      setState(() {
        _isListening = true;
        _statusMessage = "Listening for 'blueberry'...";
      });
    } on VoiceProcessorException catch(e) {
      _errorCallback(PicovoiceException(e.message!));
    }
  }

  Future<void> _stopListening() async {
    await _voiceProcessorSubscription?.cancel();
    _voiceProcessorSubscription = null;

    final voiceProcessor = VoiceProcessor.instance;
    if(voiceProcessor.isRecording) {
      await voiceProcessor.stop();
    }

    await _porcupine?.delete();
    _porcupine = null;
    await _cheetah?.delete();
    _cheetah = null;

    setState(() {
      _isListening = false;
      _isTranscribing = false;
      _statusMessage = "Press the mic button to start listening.";
    });
  }

  void _setInitialState() async {
    // Add Ritz-Carlton marker
    _markers.add(
      const Marker(
        markerId: MarkerId('ritzCarlton'),
        position: _ritzCarltonSFO,
        infoWindow: InfoWindow(title: 'The Ritz-Carlton, San Francisco'),
      ),
    );

    try {
      // Get current location to adjust camera
      final location = await _determinePosition();
      final currentLatLng = LatLng(location.latitude, location.longitude);

      // Adjust map to show both the Ritz and the user's location
      _updateCameraBounds(currentLatLng);

    } catch (e) {
      print(e);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('現在地の取得に失敗しました。リッツ・カールトンのみ表示します。')),
      );
    }

    // Re-render the screen to show the Ritz marker
    setState(() {});
  }

  void _updateCameraBounds(LatLng currentUserPosition) async {
    final GoogleMapController controller = await _controller.future;

    final double minLat = min(currentUserPosition.latitude, _ritzCarltonSFO.latitude);
    final double maxLat = max(currentUserPosition.latitude, _ritzCarltonSFO.latitude);
    final double minLng = min(currentUserPosition.longitude, _ritzCarltonSFO.longitude);
    final double maxLng = max(currentUserPosition.longitude, _ritzCarltonSFO.longitude);

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 70.0));
  }

  Future<void> _goToCurrentLocation() async {
    try {
      final location = await _determinePosition();
      final latLng = LatLng(location.latitude, location.longitude);
      final GoogleMapController controller = await _controller.future;

      controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: latLng,
            zoom: 16.0,
          ),
        ),
      );
    } catch (e) {
      print(e);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('現在地の取得に失敗しました。')),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Maps App'),
        backgroundColor: Colors.green[700],
      ),
      body: Column(
        children: [
          Expanded(
            child: GoogleMap(
              initialCameraPosition: _initialCameraPosition,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              markers: _markers,
              onMapCreated: (controller) {
                _controller.complete(controller);
              },
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            color: Colors.grey[200],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_statusMessage, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8.0),
                Text(_transcript),
              ],
            ),
          )
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(left: 32.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            FloatingActionButton(
              onPressed: _goToCurrentLocation,
              child: const Icon(Icons.my_location),
            ),
            FloatingActionButton(
              onPressed: _toggleListening,
              backgroundColor: _isListening ? Colors.red : Colors.blue,
              child: Icon(_isListening ? Icons.mic_off : Icons.mic),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  /// Determines the current position of the device.
  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
          'Location permissions are permanently denied, we cannot request permissions.');
    }

    return await Geolocator.getCurrentPosition();
  }
}