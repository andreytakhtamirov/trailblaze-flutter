import 'package:flutter/material.dart';
import 'package:trailblaze/data/instruction.dart';
import 'package:trailblaze/data/trailblaze_route.dart';
import 'package:trailblaze/util/format_helper.dart';
import 'package:trailblaze/util/navigation_helper.dart';
import 'package:trailblaze/widgets/map/icon_button_small.dart';

class NavigationPanel extends StatefulWidget {
  const NavigationPanel({
    Key? key,
    required this.route,
    required this.onExit,
  }) : super(key: key);

  final TrailblazeRoute? route;
  final Function() onExit;

  @override
  State<NavigationPanel> createState() => _NavigationPanelState();
}

class _NavigationPanelState extends State<NavigationPanel> {

  @override
  initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        FormatHelper.formatDistance(widget.route?.distance),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        FormatHelper.formatDuration(widget.route?.duration),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  IconButtonSmall(
                    icon: Icons.close_rounded,
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    iconFontSize: 32,
                    onTap: widget.onExit,
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
