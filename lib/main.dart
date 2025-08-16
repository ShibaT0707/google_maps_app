import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import 'api_key.dart';

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
  final _searchController = TextEditingController();
  List<dynamic> _placeSuggestions = [];

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


  void _getAutocompleteSuggestions(String input) async {
    if (input.isEmpty) {
      setState(() {
        _placeSuggestions = [];
      });
      return;
    }

    if (googleApiKey == "YOUR_API_KEY") {
      // APIキーが設定されていない場合は、何もしない
      return;
    }

    String apiKey = googleApiKey;
    String url =
        'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$input&key=$apiKey&language=ja';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      if (decoded['status'] == 'OK') {
        setState(() {
          _placeSuggestions = decoded['predictions'];
        });
      } else {
        setState(() {
          _placeSuggestions = [];
        });
      }
    } else {
      print('Failed to load suggestions');
    }
  }

  Future<void> _goToPlace(String placeId) async {
    if (googleApiKey == "YOUR_API_KEY") {
      return;
    }
    final String url =
        'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$googleApiKey&language=ja';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      if (decoded['status'] == 'OK') {
        final result = decoded['result'];
        final lat = result['geometry']['location']['lat'];
        final lng = result['geometry']['location']['lng'];
        final latLng = LatLng(lat, lng);

        final controller = await _controller.future;
        controller.animateCamera(CameraUpdate.newCameraPosition(
          CameraPosition(target: latLng, zoom: 16.0),
        ));

        setState(() {
          _markers.removeWhere((m) => m.markerId.value != 'ritzCarlton');
          _markers.add(
            Marker(
              markerId: MarkerId(placeId),
              position: latLng,
              infoWindow: InfoWindow(
                title: result['name'],
                snippet: result['formatted_address'],
              ),
            ),
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: '行きたい場所を検索',
            fillColor: Colors.white,
            filled: true,
            prefixIcon: const Icon(Icons.search),
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            isDense: true,
          ),
          onChanged: _getAutocompleteSuggestions,
        ),
        backgroundColor: Colors.green[700],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialCameraPosition,
            myLocationEnabled: true, // Enable the blue dot for current location
            myLocationButtonEnabled: false, // We use our own button
            markers: _markers,
            onMapCreated: (controller) {
              _controller.complete(controller);
            },
          ),
          if (_placeSuggestions.isNotEmpty)
            Container(
              color: Colors.white,
              child: ListView.builder(
                itemCount: _placeSuggestions.length,
                itemBuilder: (context, index) {
                  final suggestion = _placeSuggestions[index];
                  return ListTile(
                    title: Text(suggestion['description']),
                    onTap: () {
                      _goToPlace(suggestion['place_id']);
                      setState(() {
                        _searchController.clear();
                        _placeSuggestions = [];
                      });
                    },
                  );
                },
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