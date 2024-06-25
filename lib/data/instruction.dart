import 'dart:core';

import 'package:trailblaze/constants/navigation_constants.dart';
import 'package:turf/turf.dart' as turf;

class Instruction {
  late final String text;
  late final String streetName;
  late final num distance;
  late final int time;
  late final Sign sign;
  late final int? exitNumber;
  late final double? turnAngle;
  late final List<turf.Position> coordinates = [];

  Instruction(dynamic jsonObject, List<List<num>> coordinates) {
    text = jsonObject['text'];
    streetName = jsonObject['street_name'];
    distance = jsonObject['distance'];
    time = jsonObject['time'];
    sign = Sign.fromValue(jsonObject['sign']);
    exitNumber = jsonObject['exit_number'];
    turnAngle = jsonObject['turn_angle'];

    List<int> interval = (jsonObject['interval'] as List<dynamic>).cast<int>();
    final first = interval.first;
    final last = interval.last;

    for (int i = first; i <= last; i++) {
      List<num> c = coordinates[i];
      double latitude = c[0].toDouble();
      double longitude = c[1].toDouble();
      turf.Position position = turf.Position(latitude, longitude);
      this.coordinates.add(position);
    }
  }

  @override
  String toString() {
    return 'Instruction\n{text: $text, streetName: $streetName, distance: $distance, time: $time, sign: $sign, exitNumber: $exitNumber, turnAngle: $turnAngle}}';
  }
}
