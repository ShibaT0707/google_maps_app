import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

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
  // Use the base class controller to hold either type of controller.
  GoogleMapViewController? _mapController;
  bool _isNavigationSessionInitialized = false;
  bool _isNavigating = false;
  List<NavigationWaypoint> _destinations = [];
  bool _isRouteLoaded = false;

  PermissionStatus _locationPermissionStatus = PermissionStatus.denied;
  StreamSubscription<RoadSnappedLocationUpdatedEvent>? _locationSubscription;
  LatLng? _currentUserPosition;

  static const _ritzCarltonSFO =
      LatLng(latitude: 37.788302, longitude: -122.403209);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final status = await Permission.location.request();
    setState(() {
      _locationPermissionStatus = status;
    });

    if (status == PermissionStatus.granted) {
      // Only initialize navigation if permission is granted.
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

  Future<void> _startListeningToLocation(GoogleMapViewController controller) async {
    await _locationSubscription?.cancel(); // Cancel any existing listener.
    _locationSubscription =
        await GoogleMapsNavigator.setRoadSnappedLocationUpdatedListener((event) {
      final newPosition = event.location;
      if (mounted && _currentUserPosition != newPosition) {
        setState(() {
          _currentUserPosition = newPosition;
        });

        if (_currentUserPosition != null) {
          controller
              .animateCamera(
            CameraUpdate.newLatLngZoom(_currentUserPosition!, 14),
          )
              .then((_) {
            _locationSubscription?.cancel();
          });
        }
      }
    });
  }

  void _onMapViewCreated(GoogleMapViewController controller) {
    setState(() {
      _mapController = controller;
    });
    _mapController?.setMyLocationEnabled(true);
    _startListeningToLocation(controller);
  }

  void _onNavigationViewCreated(GoogleNavigationViewController controller) {
     setState(() {
      _mapController = controller;
    });
    _mapController?.setMyLocationEnabled(true);
    _startListeningToLocation(controller);
  }

  void _calculateAndShowRoute() {
    if (_currentUserPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('現在地が取得できていません。少し待ってから再度お試しください。')),
      );
      return;
    }

    final destination =
        NavigationWaypoint(title: 'The Ritz-Carlton, San Francisco', target: _ritzCarltonSFO);

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

  Widget _buildBody() {
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
            initialCameraPosition: CameraPosition(
                target: _currentUserPosition ??
                    const LatLng(latitude: 37.7749, longitude: -122.4194),
                zoom: 14),
            initialNavigationUIEnabledPreference:
                NavigationUIEnabledPreference.automatic,
          )
        : GoogleMapsMapView(
            key: const ValueKey('map_view'),
            onViewCreated: _onMapViewCreated,
            initialCameraPosition: CameraPosition(
                target: _currentUserPosition ??
                    const LatLng(latitude: 37.7749, longitude: -122.4194),
                zoom: 14),
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
                    GoogleMapsNavigator.clearDestinations();
                  });
                },
              )
            : null,
      ),
      body: _buildBody(),
      floatingActionButton: _isNavigationSessionInitialized && !_isNavigating
          ? Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FloatingActionButton(
                  onPressed: _calculateAndShowRoute,
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