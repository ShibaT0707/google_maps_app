import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_app/speech_service.dart';
import 'package:speech_to_text/speech_to_text.dart';

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

// Enum to manage the listening state
enum ListeningState { waitingForWakeWord, listeningForCommand }

class _MapScreenState extends State<MapScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  final Set<Marker> _markers = {};
  final SpeechService _speechService = SpeechService();

  String _lastRecognizedText = '';
  ListeningState _listeningState = ListeningState.waitingForWakeWord;

  static const _wakeWord = "blueberry";
  static const _wakeWordLocale = "en_US";
  static const _commandLocale = "ja_JP";

  static const _ritzCarltonSFO = LatLng(37.788302, -122.403209);
  static const _initialCameraPosition = CameraPosition(
    target: _ritzCarltonSFO,
    zoom: 14.0,
  );

  @override
  void initState() {
    super.initState();
    _setInitialState();
    _initializeSpeech();
  }

  void _initializeSpeech() async {
    final hasPermission = await _speechService.initialize(
      onResult: _onSpeechResult,
      onStatusChanged: _onStatusChanged,
    );
    if (hasPermission) {
      _startWakeWordListener();
    }
  }

  @override
  void dispose() {
    _speechService.stop();
    super.dispose();
  }

  void _startWakeWordListener() {
    print("--- Listening for wake word '$_wakeWord' ---");
    setState(() {
      _listeningState = ListeningState.waitingForWakeWord;
      _lastRecognizedText = '';
    });
    _speechService.listen(
      localeId: _wakeWordLocale,
      listenFor: const Duration(days: 1), // Listen indefinitely
    );
  }

  void _startCommandListener() {
    print("--- Wake word detected! Listening for command. ---");
    setState(() {
      _listeningState = ListeningState.listeningForCommand;
      _lastRecognizedText = '...';
    });
    _speechService.listen(
      localeId: _commandLocale,
      pauseFor: const Duration(seconds: 3), // End after 3s of silence
    );
  }

  void _onStatusChanged(String status) {
    if (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) {
      if (_listeningState == ListeningState.listeningForCommand) {
        // If command listening ends, go back to wake word listening
        print("--- Command listening ended. Returning to wake word listening. ---");
        _startWakeWordListener();
      } else {
        // If wake word listening stops for any reason (e.g. error, timeout), restart it.
        print("--- Wake word listening stopped unexpectedly. Restarting. ---");
        _speechService.stop();
        Future.delayed(const Duration(milliseconds: 500), _startWakeWordListener);
      }
    }
  }

  void _onSpeechResult(String text) {
    if (_listeningState == ListeningState.waitingForWakeWord) {
      // Using contains for more robust detection
      if (text.trim().toLowerCase().contains(_wakeWord)) {
        _speechService.stop(); // Stop the current listener
        _startCommandListener();
      }
    } else { // listeningForCommand
      setState(() {
        _lastRecognizedText = text;
      });
    }
  }

  void _setInitialState() async {
    _markers.add(
      const Marker(
        markerId: MarkerId('ritzCarlton'),
        position: _ritzCarltonSFO,
        infoWindow: InfoWindow(title: 'The Ritz-Carlton, San Francisco'),
      ),
    );
    try {
      final location = await _determinePosition();
      final currentLatLng = LatLng(location.latitude, location.longitude);
      _updateCameraBounds(currentLatLng);
    } catch (e) {
      print(e);
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('現在地の取得に失敗しました。リッツ・カールトンのみ表示します。')),
        );
      }
    }
    if(mounted) {
      setState(() {});
    }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('現在地の取得に失敗しました。')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Maps App'),
        backgroundColor: Colors.green[700],
      ),
      body: Stack(
        children: <Widget>[
          GoogleMap(
            initialCameraPosition: _initialCameraPosition,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            markers: _markers,
            onMapCreated: (controller) {
              _controller.complete(controller);
            },
          ),
          if (_listeningState == ListeningState.listeningForCommand)
            Center(
              child: Container(
                padding: const EdgeInsets.all(16.0),
                color: Colors.black54,
                child: Text(
                  _lastRecognizedText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24.0,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _goToCurrentLocation,
        child: const Icon(Icons.my_location),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    );
  }

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