import 'dart:math';

import 'package:trailblaze/data/instruction.dart';
import 'package:trailblaze/data/trailblaze_route.dart';
import 'package:turf/distance.dart';
import 'package:turf/helpers.dart';

class NavigationHelper {
  final TrailblazeRoute _route;
  int _currentInstruction = 0;

  NavigationHelper(this._route);

  Instruction? getCurrentInstruction() {
    return _route.instructions?[_currentInstruction];
  }

  Instruction? nextInstruction() {
    _currentInstruction++;
    return getCurrentInstruction();
  }

  Instruction? previousInstruction() {
    _currentInstruction--;
    return getCurrentInstruction();
  }

  static bool isPositionInsideInstruction(
      Position position, Instruction instruction) {
    const tolerance = 0.002;
    final start = instruction.coordinates.first;
    final end = instruction.coordinates.last;
    double minX = min(start.lat.toDouble(), end.lat.toDouble());
    double maxX = max(start.lat.toDouble(), end.lat.toDouble());
    double minY = min(start.lng.toDouble(), end.lng.toDouble());
    double maxY = max(start.lng.toDouble(), end.lng.toDouble());

    if (position.lat >= minX - tolerance &&
        position.lat <= maxX + tolerance &&
        position.lng >= minY - tolerance &&
        position.lng <= maxY + tolerance) {
      return true;
    }

    return false;
  }
}
