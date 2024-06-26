import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbm;
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:trailblaze/constants/map_constants.dart';
import 'package:trailblaze/constants/ui_control_constants.dart';
import 'package:trailblaze/data/feature.dart';
import 'package:trailblaze/screens/distance_selector_screen.dart';
import 'package:trailblaze/util/firebase_helper.dart';
import 'package:trailblaze/util/format_helper.dart';
import 'package:trailblaze/widgets/list_items/feature_item.dart';
import 'package:trailblaze/widgets/map/icon_button_small.dart';

class FeaturesPanel extends StatelessWidget {
  const FeaturesPanel({
    Key? key,
    required this.panelController,
    required this.pageController,
    required this.features,
    this.userLocation,
    this.selectedDistanceMeters,
    required this.onFeaturePageChanged,
    required this.onDistanceChanged,
  }) : super(key: key);
  final PanelController panelController;
  final PageController pageController;
  final List<Feature>? features;
  final mbm.Position? userLocation;
  final double? selectedDistanceMeters;
  final Function(int page) onFeaturePageChanged;
  final Function(double distance) onDistanceChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                textAlign: TextAlign.center,
                "Nearby Parks – ${FormatHelper.formatDistance(selectedDistanceMeters)}",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        IgnorePointer(
          ignoring: panelController.isAttached && panelController.isPanelClosed,
          child: SizedBox(
            height: kPanelFeaturesMaxHeight * 0.5,
            child: features != null && features!.isNotEmpty
                ? PageView.builder(
                    controller: pageController,
                    scrollDirection: Axis.horizontal,
                    itemCount: features?.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: FeatureItem(
                          feature: features![index],
                          userLocation: userLocation,
                          onClicked: () {
                            pageController.animateToPage(
                              index,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.ease,
                            );
                          },
                        ),
                      );
                    },
                    onPageChanged: onFeaturePageChanged,
                  )
                : features == null
                    ? const Center(
                        child: CircularProgressIndicator(),
                      )
                    : const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 52),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  "No Features Found.\nTry expanding the search distance.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
          ),
        ),
        SizedBox(
          height: kPanelFeaturesMaxHeight * 0.2,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: IconButtonSmall(
              text:
                  "Target Distance ${FormatHelper.formatDistance(selectedDistanceMeters, noRemainder: true)}",
              textFontSize: 20,
              icon: Icons.edit,
              backgroundColor: Theme.of(context).colorScheme.tertiary,
              foregroundColor: Colors.white,
              onTap: () async {
                FirebaseHelper.logScreen("DistanceSelectorScreen(Features)");
                final distanceKm = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DistanceSelectorScreen(
                      center: [userLocation!.lng.toDouble(), userLocation!.lat.toDouble()],
                      initialDistanceMeters: selectedDistanceMeters ??
                          kDefaultFeatureDistanceMeters,
                      minDistanceKm: kMinFeatureDistanceMeters / 1000,
                      maxDistanceKm: kMaxFeatureDistanceMeters / 1000,
                      minZoom: kMinFeatureFilterCameraZoom,
                      maxZoom: kMaxFeatureFilterCameraZoom,
                    ),
                  ),
                );

                if (distanceKm == null) {
                  return;
                }

                onDistanceChanged(distanceKm * 1000);
              },
              // onTap: _onSelectDistanceTap,
            ),
          ),
        )
      ],
    );
  }
}
