import 'dart:async';

import 'package:flutter/material.dart';
import 'package:places_service/places_service.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.placesService});
  final PlacesService placesService;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  List<PlacesAutoCompletePrediction> _predictions = [];
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (value.isNotEmpty) {
        final result = await widget.placesService.getAutoComplete(value);
        if (result != null) {
          setState(() {
            _predictions = result;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _predictions = [];
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('場所を検索'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '地名、住所、郵便番号などを入力',
                border: OutlineInputBorder(),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _predictions.length,
              itemBuilder: (context, index) {
                final prediction = _predictions[index];
                return ListTile(
                  title: Text(prediction.description ?? ''),
                  onTap: () {
                    Navigator.pop(context, prediction);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
