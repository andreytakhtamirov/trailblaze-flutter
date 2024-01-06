import 'package:dartz/dartz.dart' as dartz;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:trailblaze/data/feature.dart';
import 'package:trailblaze/requests/explore.dart';
import 'package:trailblaze/util/ui_helper.dart';

class FeatureManager {
  static Future<List<Feature>> loadFeatures(
      BuildContext context, int distanceMeters, geo.Position position) async {
    final dartz.Either<Map<int, String>, List<dynamic>?> response;
    response = await getFeatures(
        [position.longitude, position.latitude], distanceMeters);

    List<dynamic>? jsonData;

    response.fold(
      (error) => {
        if (error.keys.first == 404)
          {UiHelper.showSnackBar(context, error.values.first)}
        else
          {UiHelper.showSnackBar(context, "An unknown error occurred.")}
      },
      (data) => {jsonData = data},
    );

    if (jsonData == null || jsonData?.length == null) {
      return [];
    }

    List<Feature> features =
        jsonData!.map((json) => Feature.fromJson(json)).toList();

    return features;
  }
}
