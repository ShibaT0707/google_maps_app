import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:places_service/places_service.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'search_screen.dart';

Future<void> main() async {
  await dotenv.load(fileName: "assets/.env");
  runApp(const MyApp());
}

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
  final _placesService = PlacesService();
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  String _recognizedWords = '';
  bool _wakeWordDetected = false;
  String _textAfterWakeWord = '';

  GoogleMapViewController? _mapController;
  bool _isNavigationSessionInitialized = false;
  bool _isNavigating = false;
  List<NavigationWaypoint> _destinations = [];
  bool _isRouteLoaded = false;
  bool _cameraCentered = false;

  PermissionStatus _locationPermissionStatus = PermissionStatus.denied;
  StreamSubscription<RoadSnappedLocationUpdatedEvent>? _locationSubscription;
  LatLng? _currentUserPosition;
  LatLng? _destination;
  String? _destinationName;

  @override
  void initState() {
    super.initState();
    _init();
    _initSpeech();
    _placesService.initialize(apiKey: dotenv.env['GOOGLE_MAPS_API_KEY']!);
  }

  Future<void> _initSpeech() async {
    _speechEnabled = await _speechToText.initialize();
    setState(() {});
  }

  void _startListening() async {
    setState(() {
      _wakeWordDetected = false;
      _textAfterWakeWord = '';
      _recognizedWords = '';
    });
    await _speechToText.listen(onResult: _onSpeechResult, localeId: "ja_JP");
    setState(() {});
  }

  void _stopListening() async {
    await _speechToText.stop();
    setState(() {});
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      _recognizedWords = result.recognizedWords;
      const wakeWord = "ヘイジュール";
      if (!_wakeWordDetected && _recognizedWords.contains(wakeWord)) {
        _wakeWordDetected = true;
      }
      if (_wakeWordDetected) {
        final wakeWordIndex = _recognizedWords.indexOf(wakeWord);
        if (wakeWordIndex != -1) {
          _textAfterWakeWord =
              _recognizedWords.substring(wakeWordIndex + wakeWord.length).trim();
        }
      }
    });
  }

  Future<void> _init() async {
    final status = await Permission.location.request();
    setState(() {
      _locationPermissionStatus = status;
    });

    if (status == PermissionStatus.granted) {
      await _initializeNavigationSession();
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    if (_isNavigationSessionInitialized) {
      GoogleMapsNavigator.cleanup();
    }
    super.dispose();
  }

  Future<void> _initializeNavigationSession() async {
    if (!await GoogleMapsNavigator.areTermsAccepted()) {
      await GoogleMapsNavigator.showTermsAndConditionsDialog(
        'Google Maps App',
        'Company Name',
      );
    }

    if (await GoogleMapsNavigator.areTermsAccepted()) {
      await GoogleMapsNavigator.initializeNavigationSession(
        taskRemovedBehavior: TaskRemovedBehavior.continueService,
      );
      setState(() {
        _isNavigationSessionInitialized = true;
      });
    }
  }

  void _addDestinationMarker(GoogleMapViewController controller) {
    controller.clearMarkers();
    if (_destination != null) {
      controller.addMarkers([
        MarkerOptions(
          position: _destination!,
          infoWindow: InfoWindow(title: _destinationName ?? 'Destination'),
        ),
      ]);
    }
  }

  Future<void> _startListeningToLocation(GoogleMapViewController controller) async {
    await _locationSubscription?.cancel();
    _locationSubscription =
        await GoogleMapsNavigator.setRoadSnappedLocationUpdatedListener((event) {
      if (mounted) {
        setState(() {
          _currentUserPosition = event.location;
        });

        if (!_cameraCentered && _currentUserPosition != null) {
          controller.animateCamera(
            CameraUpdate.newLatLngZoom(_currentUserPosition!, 14),
          );
          setState(() {
            _cameraCentered = true;
          });
        }
      }
    });
  }

  void _onMapViewCreated(GoogleMapViewController controller) {
    setState(() {
      _mapController = controller;
      _cameraCentered = false;
    });
    controller.setMyLocationEnabled(true);
    _addDestinationMarker(controller);
    _startListeningToLocation(controller);
  }

  void _onNavigationViewCreated(GoogleNavigationViewController controller) {
    setState(() {
      _mapController = controller;
      _cameraCentered = false;
    });
    controller.setMyLocationEnabled(true);
    _addDestinationMarker(controller);
    _startListeningToLocation(controller);
  }

  void _calculateAndShowRoute() {
    // The button is disabled if _currentUserPosition is null, so this check is redundant but safe.
    if (_currentUserPosition == null || _destination == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('現在地または目的地が設定されていません。')),
      );
      return;
    }

    final destination =
        NavigationWaypoint(title: _destinationName ?? 'Destination', target: _destination!);

    GoogleMapsNavigator.setDestinations(Destinations(
      waypoints: [destination],
      displayOptions: NavigationDisplayOptions(showDestinationMarkers: true),
    )).then((result) {
      if (result == NavigationRouteStatus.statusOk) {
        setState(() {
          _destinations = [destination];
          _isRouteLoaded = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('経路が見つかりました。')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('経路の取得に失敗しました: $result')),
        );
      }
    });
  }

  Future<void> _showSearch() async {
    final prediction = await Navigator.push<PlacesAutoCompleteResult>(
      context,
      MaterialPageRoute(
        builder: (context) => SearchScreen(placesService: _placesService),
      ),
    );

    if (prediction != null && prediction.placeId != null) {
      final details = await _placesService.getPlaceDetails(prediction.placeId!);
      if (details != null && details.lat != null && details.lng != null) {
        setState(() {
          _destination = LatLng(latitude: details.lat!, longitude: details.lng!);
          _destinationName = prediction.description;
          _isRouteLoaded = false;
        });

        if (_mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(_destination!, 14),
          );
          _addDestinationMarker(_mapController!);
        }
      }
    }
  }

  Widget _buildBody() {
    const initialCameraPosition = CameraPosition(
        target: LatLng(latitude: 37.7749, longitude: -122.4194),
        zoom: 14);

    if (_locationPermissionStatus != PermissionStatus.granted) {
      return const Center(child: Text('位置情報の許可が必要です。'));
    }
    if (!_isNavigationSessionInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return _isNavigating
        ? GoogleMapsNavigationView(
            key: const ValueKey('navigation_view'),
            onViewCreated: _onNavigationViewCreated,
            initialCameraPosition: initialCameraPosition,
            initialNavigationUIEnabledPreference:
                NavigationUIEnabledPreference.automatic,
          )
        : GoogleMapsMapView(
            key: const ValueKey('map_view'),
            onViewCreated: _onMapViewCreated,
            initialCameraPosition: initialCameraPosition,
          );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNavigating ? 'ナビゲーション中' : 'Google Maps App'),
        backgroundColor: Colors.green[700],
        leading: _isNavigating
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _isNavigating = false;
                    _isRouteLoaded = false;
                    _destinations = [];
                    _cameraCentered = false; // Reset camera lock for next time
                    GoogleMapsNavigator.clearDestinations();
                  });
                },
              )
            : null,
        actions: [
          if (!_isNavigating)
            IconButton(
              icon: Icon(_speechToText.isNotListening ? Icons.mic_off : Icons.mic),
              onPressed: _speechToText.isNotListening ? _startListening : _stopListening,
            ),
          if (!_isNavigating)
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: _showSearch,
            ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          _buildBody(),
          if (_wakeWordDetected)
            Center(
              child: Container(
                padding: const EdgeInsets.all(16.0),
                color: Colors.black.withOpacity(0.5),
                child: Text(
                  _textAfterWakeWord,
                  style: const TextStyle(color: Colors.white, fontSize: 24.0),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _isNavigationSessionInitialized && !_isNavigating
          ? Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FloatingActionButton(
                  onPressed: _currentUserPosition == null || _destination == null
                      ? null
                      : _calculateAndShowRoute,
                  backgroundColor: _currentUserPosition == null || _destination == null
                      ? Colors.grey
                      : Theme.of(context).colorScheme.secondary,
                  child: const Icon(Icons.directions),
                ),
                const SizedBox(height: 16),
                if (_isRouteLoaded)
                  FloatingActionButton.extended(
                    onPressed: () {
                      setState(() {
                        _isNavigating = true;
                      });
                    },
                    label: const Text('Navigation'),
                    icon: const Icon(Icons.navigation),
                  ),
              ],
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    );
  }
}