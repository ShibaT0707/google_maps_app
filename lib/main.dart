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

class _MapScreenState extends State<MapScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  final Set<Marker> _markers = {};
  final SpeechService _speechService = SpeechService();
  String _lastRecognizedText = '';
  bool _isListening = false;

  static const _ritzCarltonSFO = LatLng(37.788302, -122.403209);

  static const _initialCameraPosition = CameraPosition(
    target: _ritzCarltonSFO,
    zoom: 14.0,
  );

  @override
  void initState() {
    super.initState();
    _setInitialState();
    _speechService.initialize(
      onResult: _onSpeechResult,
      onStatusChanged: _onStatusChanged,
    );
  }

  @override
  void dispose() {
    _speechService.stopListening();
    super.dispose();
  }

  void _onStatusChanged(String status) {
    setState(() {
      _isListening = status == SpeechToText.listeningStatus;
    });
  }

  void _onSpeechResult(String text) {
    setState(() {
      _lastRecognizedText = text;
    });

    final lowerCaseText = text.toLowerCase();
    if (lowerCaseText.startsWith("ok jules") || lowerCaseText.startsWith("okay jules")) {
      final command = lowerCaseText.replaceFirst(RegExp(r'ok(ay)? jules\s*'), '');
      if (command.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('認識されたコマンド: $command')),
        );
      }
    }
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
          if (_isListening)
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