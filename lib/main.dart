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
  GoogleMapViewController? _mapController;
  bool _isNavigationSessionInitialized = false;
  bool _isNavigating = false;
  List<NavigationWaypoint> _destinations = [];
  bool _isRouteLoaded = false;

  PermissionStatus _locationPermissionStatus = PermissionStatus.denied;

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
      await _initializeNavigationSession();
    }
  }

  @override
  void dispose() {
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
    controller.addMarkers([
      MarkerOptions(
        position: _ritzCarltonSFO,
        infoWindow: const InfoWindow(title: 'The Ritz-Carlton'),
      ),
    ]);
  }

  Future<void> _centerOnUserLocation(GoogleMapViewController controller) async {
    final location = await controller.getMyLocation();
    if (location != null) {
      controller.animateCamera(
        CameraUpdate.newLatLngZoom(location, 14),
      );
    }
  }

  void _onMapViewCreated(GoogleMapViewController controller) {
    setState(() {
      _mapController = controller;
    });
    controller.setMyLocationEnabled(true);
    _addDestinationMarker(controller);
    _centerOnUserLocation(controller);
  }

  void _onNavigationViewCreated(GoogleNavigationViewController controller) {
    setState(() {
      _mapController = controller;
    });
    controller.setMyLocationEnabled(true);
    _addDestinationMarker(controller);
    _centerOnUserLocation(controller);
  }

  void _calculateAndShowRoute() async {
    if (_mapController == null) return;

    final position = await _mapController!.getMyLocation();

    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('現在地が取得できていません。GPSを確認して再度お試しください。')),
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
    // We are not using a state variable for the user's position anymore, so we can define a default initial camera position.
    // The _centerOnUserLocation method will animate to the user's location once the view is created.
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