import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:places_service/places_service.dart';
import 'package:porcupine_flutter/porcupine.dart';
import 'package:porcupine_flutter/porcupine_error.dart';
import 'package:cheetah_flutter/cheetah.dart';
import 'package:cheetah_flutter/cheetah_error.dart';
import 'package:flutter_voice_processor/flutter_voice_processor.dart';
import 'dart:io' show Platform;
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

  VoiceProcessor? _voiceProcessor;
  Porcupine? _porcupine;
  Cheetah? _cheetah;
  bool _isListening = false;
  String _transcript = "";

  @override
  void initState() {
    super.initState();
    _init();
    _placesService.initialize(apiKey: dotenv.env['GOOGLE_MAPS_API_KEY']!);
  }

  final String _accessKey = "Egp/2jlwIi6904XG3pGI+EftUJ4/6ubuap3a7hHWK3jKopEPZ2rb/w==";

  Future<void> _init() async {
    final status = await Permission.location.request();
    setState(() {
      _locationPermissionStatus = status;
    });

    if (status == PermissionStatus.granted) {
      await _initializeNavigationSession();
      _initPicovoice();
    }
  }

  void _initPicovoice() async {
    String keywordPath;
    if (Platform.isAndroid) {
      keywordPath = "assets/picovoice/blueberry_android.ppn";
    } else if (Platform.isIOS) {
      keywordPath = "assets/picovoice/blueberry_ios.ppn";
    } else {
      print("Unsupported platform");
      return;
    }

    try {
      _voiceProcessor = VoiceProcessor.instance;
      _porcupine = await Porcupine.fromKeywordPaths(
        _accessKey,
        [keywordPath],
        modelPath: "assets/picovoice/porcupine_params.pv",
      );
      _voiceProcessor?.addFrameListener(_porcupineFrameListener);
      _voiceProcessor?.start(_porcupine!.frameLength, _porcupine!.sampleRate);
    } on PorcupineException catch (e) {
      _errorCallback(e);
    }
  }

  void _wakeWordDetected() async {
    setState(() {
      _isListening = true;
      _transcript = "Listening...";
    });
    _voiceProcessor?.removeFrameListener(_porcupineFrameListener);
    await _startCheetah();
  }

  void _errorCallback(dynamic error) {
    setState(() {
      _transcript = error.message!;
    });
  }

  void _porcupineFrameListener(List<int> frame) async {
    if (_porcupine == null) return;
    try {
      final keywordIndex = await _porcupine!.process(frame);
      if (keywordIndex >= 0) {
        _wakeWordDetected();
      }
    } on PorcupineException catch (e) {
      _errorCallback(e);
    }
  }

  Future<void> _startCheetah() async {
    try {
      _cheetah = await Cheetah.create(
        _accessKey,
        "assets/picovoice/cheetah_params_ja.pv",
        enableAutomaticPunctuation: true,
      );
      _voiceProcessor?.addFrameListener(_cheetahFrameListener);
    } on CheetahException catch (e) {
      _errorCallback(e);
    }
  }

  Future<void> _stopCheetahAndRestartPorcupine() async {
    _voiceProcessor?.removeFrameListener(_cheetahFrameListener);
    setState(() {
      _isListening = false;
    });
    await _cheetah?.delete();
    _cheetah = null;
    await _startPorcupine();
  }

  void _cheetahFrameListener(List<int> frame) async {
    if (_cheetah == null) return;
    try {
      final partialResult = await _cheetah!.process(frame);
      if (partialResult.transcript.isNotEmpty) {
        setState(() {
          _transcript = _transcript == "Listening..."
              ? partialResult.transcript
              : _transcript + partialResult.transcript;
        });
      }

      if (partialResult.isEndpoint) {
        final finalResult = await _cheetah!.flush();
        setState(() {
          _transcript += finalResult.transcript;
        });
        await _stopCheetahAndRestartPorcupine();
      }
    } on CheetahException catch (e) {
      _errorCallback(e);
    }
  }

  Future<void> _startPorcupine() async {
    _voiceProcessor?.addFrameListener(_porcupineFrameListener);
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    if (_isNavigationSessionInitialized) {
      GoogleMapsNavigator.cleanup();
    }
    _voiceProcessor?.stop();
    _porcupine?.delete();
    _cheetah?.delete();
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

    return Stack(
      children: [
        _isNavigating
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
              ),
        if (_isListening || _transcript.isNotEmpty)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.5),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    _transcript,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24.0,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
      ],
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
              icon: const Icon(Icons.search),
              onPressed: _showSearch,
            ),
        ],
      ),
      body: _buildBody(),
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