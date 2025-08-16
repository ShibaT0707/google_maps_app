import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import 'directions_repository.dart';

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
  final DirectionsRepository _directionsRepository = DirectionsRepository();
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  String _routeInfo = '';
  int _selectedRouteIndex = 0;
  Map<String, dynamic>? _directionsInfo;


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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('現在地の取得に失敗しました。リッツ・カールトンのみ表示します。')),
      );
    }
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
          CameraPosition(target: latLng, zoom: 16.0),
        ),
      );
    } catch (e) {
      print(e);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('現在地の取得に失敗しました。')),
      );
    }
  }

  Future<void> _getRoute() async {
    try {
      final location = await _determinePosition();
      final origin = '${location.latitude},${location.longitude}';
      final destination = '${_ritzCarltonSFO.latitude},${_ritzCarltonSFO.longitude}';

      final directions = await _directionsRepository.getDirections(
        origin: origin,
        destination: destination,
      );

      if (directions == null || directions['routes'].isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ルートが見つかりませんでした。')),
        );
        return;
      }

      setState(() {
        _directionsInfo = directions;
        _selectedRouteIndex = 0; // Reset to the first route
        _updatePolylines();
        _updateRouteInfo();
      });
    } catch (e) {
      print(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ルートの取得中にエラーが発生しました: $e')),
      );
    }
  }

  void _updatePolylines() {
    if (_directionsInfo == null) return;

    _polylines.clear();
    final routes = _directionsInfo!['routes'];

    for (int i = 0; i < routes.length; i++) {
      final route = routes[i];
      final points = PolylinePoints().decodePolyline(route['overview_polyline']['points']);
      final polylineCoordinates = points.map((point) => LatLng(point.latitude, point.longitude)).toList();
      final isSelected = i == _selectedRouteIndex;

      _polylines.add(
        Polyline(
          polylineId: PolylineId('route_$i'),
          points: polylineCoordinates,
          color: isSelected ? Colors.blue : Colors.grey,
          width: isSelected ? 8 : 5,
          zIndex: isSelected ? 1 : 0,
          consumeTapEvents: true,
          onTap: () {
            setState(() {
              _selectedRouteIndex = i;
              _updateRouteInfo();
              _updatePolylines(); // Redraw polylines to reflect selection
            });
          },
        ),
      );
    }
  }

  void _updateRouteInfo() {
    if (_directionsInfo == null || _directionsInfo!['routes'].isEmpty) {
      setState(() => _routeInfo = '');
      return;
    }
    final leg = _directionsInfo!['routes'][_selectedRouteIndex]['legs'][0];
    final duration = leg['duration']['text'];
    final durationInTraffic = leg['duration_in_traffic']['text'];
    final distance = leg['distance']['text'];
    setState(() {
      _routeInfo = '$distance, $duration (渋滞考慮: $durationInTraffic)';
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Maps App'),
        backgroundColor: Colors.green[700],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialCameraPosition,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            markers: _markers,
            polylines: _polylines,
            onMapCreated: (controller) {
              _controller.complete(controller);
            },
          ),
          if (_routeInfo.isNotEmpty)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Card(
                elevation: 5,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    _routeInfo,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: _goToCurrentLocation,
            child: const Icon(Icons.my_location),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            onPressed: _getRoute,
            child: const Icon(Icons.directions),
          ),
        ],
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