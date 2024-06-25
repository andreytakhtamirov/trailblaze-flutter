import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:trailblaze/data/instruction.dart';
import 'package:trailblaze/data/trailblaze_route.dart';
import 'package:trailblaze/util/format_helper.dart';
import 'package:trailblaze/util/navigation_helper.dart';
import 'package:trailblaze/widgets/map/icon_button_small.dart';
import 'package:turf/distance.dart';
import 'package:turf/helpers.dart';

class DirectionsWidget extends StatefulWidget {
  const DirectionsWidget(this.route, {super.key});

  final TrailblazeRoute route;

  @override
  State<DirectionsWidget> createState() => _DirectionsWidgetState();
}

class _DirectionsWidgetState extends State<DirectionsWidget> {
  late final NavigationHelper helper;
  late Instruction? currentInstruction;
  late Location location;
  bool _isListening = true;
  num? distanceToInstruction = 0;

  @override
  initState() {
    super.initState();
    helper = NavigationHelper(widget.route);
    setState(() {
      currentInstruction = helper.getCurrentInstruction();
    });

    log("HERE");
    location = Location();
    location.enableBackgroundMode(enable: true);
    location.onLocationChanged.listen((event) {
      if (!mounted) {
        return;
      }
      log("LOCATION UPDATE speed: ${event.speed}, latlng :(${event.latitude},${event.longitude})");
      Instruction? closest;
      for (Instruction i in widget.route.instructions!) {
        if (NavigationHelper.isPositionInsideInstruction(
            Position(event.longitude!, event.latitude!), i)) {
          closest = i;
          setState(() {
            distanceToInstruction = distance(
              Point(coordinates: i.coordinates.last),
              Point(coordinates: Position(event.longitude!, event.latitude!)),
              Unit.meters,
            );
          });
        }
      }
      log('minimum: ${widget.route.instructions!.indexOf(closest!)}');
      setState(() {
        currentInstruction = closest;
      });
    });
  }

  @override
  void dispose() {
    location.enableBackgroundMode(enable: false);
    location.onLocationChanged.listen(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(
            milliseconds: 300,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  flex: 1,
                  child: Column(
                    children: [
                      Icon(
                        currentInstruction?.sign.icon,
                        size: 54,
                        color: Colors.white,
                      ),
                      Text(
                        FormatHelper.formatDistancePrecise(
                            distanceToInstruction),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentInstruction?.text ?? "",
                        style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                            color: Colors.white),
                      ),
                      Text(
                        currentInstruction?.streetName ?? "",
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
        Row(
          children: [
            IconButtonSmall(
              icon: Icons.plus_one,
              onTap: () {
                setState(() {
                  currentInstruction = helper.nextInstruction();
                });
              },
            ),
            IconButtonSmall(
              icon: Icons.exposure_minus_1,
              onTap: () {
                setState(() {
                  currentInstruction = helper.previousInstruction();
                });
              },
            ),
          ],
        ),
      ],
    );
  }
}
