import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:trailblaze/secrets/env_tokens.dart';
import 'package:trailblaze/secrets/secrets.dart';

final String kMapboxAccessToken =
    const Env(kEncryptionKey, kInitializationVector).mapboxAccessToken;

final double kDevicePixelRatio =
    WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
final kScreenHeight =
    WidgetsBinding.instance.platformDispatcher.views.first.display.size.height /
        kDevicePixelRatio;
final kSafeAreaPaddingBottom =
    WidgetsBinding.instance.platformDispatcher.views.first.padding.bottom /
        kDevicePixelRatio;

const int kMapFlyToDuration = 400;
const String kRouteSourceId = "route-source-id";
const String kRouteLayerId = "route-layer-id";
const double kRouteLineWidth = 6.0;
const double kRouteActiveLineOpacity = 0.9;
const double kRouteInactiveLineOpacity = 1.0;

const double kSearchBarHeight = 50;
const double kOptionsPillHeight = 40;
final double kLocationPinSize = kDevicePixelRatio / 3;
const double kFeaturePinSize = 5.0;

const kPointSelectedCameraZoomOffset = 2;
const double kPanelMinContentHeight = 70;
const double kPanelRouteInfoMinHeight = 120;
final double kPanelRouteInfoMaxHeight =
    kScreenHeight * 0.8 - kSafeAreaPaddingBottom;
final double kPanelMaxHeight = kScreenHeight / 3 - kSafeAreaPaddingBottom;
final double kPanelFeaturesMaxHeight =
    kScreenHeight / 3 - kSafeAreaPaddingBottom;
final double kPanelShuffleMaxHeight =
    kScreenHeight / 3 - kSafeAreaPaddingBottom;

const double kPanelFabHeight = kPanelMinContentHeight + 8;

final double kFeatureItemHeight = kScreenHeight / 6;

const double kDefaultMapZoom = 12;
const double kNavigationMapZoom = 18;

final CameraState kDefaultCameraState = CameraState(
    center: Point(coordinates: Position(-80.520852, 43.463355)),
    padding: MbxEdgeInsets(top: 100.0, left: 0.0, bottom: 100.0, right: 0.0),
    zoom: kDefaultMapZoom,
    bearing: 0,
    pitch: 0);

final CameraState kRouteCameraState = CameraState(
    center: Point(coordinates: Position(-80.520852, 43.463355)),
    padding: MbxEdgeInsets(top: 150, left: 40, bottom: 150, right: 40),
    zoom: kDefaultMapZoom,
    bearing: 0,
    pitch: 0);

final CameraState kPostDetailsCameraState = CameraState(
    center: Point(coordinates: Position(-80.520852, 43.463355)),
    padding: MbxEdgeInsets(top: 40, left: 80, bottom: 240, right: 80),
    zoom: kDefaultMapZoom,
    bearing: 0,
    pitch: 0);

final CameraState kFeaturesCameraState = CameraState(
    center: kDefaultCameraState.center,
    padding: MbxEdgeInsets(top: 140, left: 40, bottom: 160, right: 40),
    zoom: kDefaultCameraState.zoom,
    bearing: kDefaultCameraState.bearing,
    pitch: kDefaultCameraState.pitch);

const kMapStyleUriPrefix = 'mapbox://styles/mapbox';
const kMapStyleOutdoors = 'outdoors-v12';
const kMapStyleSatellite = 'satellite-streets-v12';
const kMapStyleDefaultUri = '$kMapStyleUriPrefix/$kMapStyleOutdoors';

const List<String> kMapStyleOptions = [
  kMapStyleOutdoors,
  kMapStyleSatellite,
];

final kMapTopOffset = Platform.isAndroid ? 8.0 : 0.0;
final kAndroidTopOffset = Platform.isAndroid ? 8.0 : 0.0;
const kMapUiPadding = 14.0;
const kCompassTopOffset = 32.0;
const kMapUiTopOffset = kMapUiPadding - 4;
const kAttributionLeftOffset = kMapUiPadding + 72.0;
const kAttributionBottomOffset = 62.0;
const kLogoLeftOffset = 4.0;
const kDirectionsWidgetOffset = 150.0;
final kFeaturesPaneOffset = kPanelMaxHeight;

final CompassSettings kDefaultCompassSettings = CompassSettings(
    position: OrnamentPosition.TOP_LEFT,
    marginTop: kMapUiTopOffset + kCompassTopOffset + kAndroidTopOffset * 4,
    marginBottom: 0,
    marginLeft: kMapUiPadding,
    marginRight: 0);

final CompassSettings kPostDetailsCompassSettings = CompassSettings(
    position: OrnamentPosition.TOP_LEFT,
    marginTop: kMapUiPadding + kCompassTopOffset + kAndroidTopOffset,
    marginBottom: 0,
    marginLeft: kMapUiPadding,
    marginRight: 0);

final CompassSettings kDirectionsCompassSettings = CompassSettings(
    position: OrnamentPosition.TOP_LEFT,
    marginTop: kMapUiPadding +
        kCompassTopOffset +
        kDirectionsWidgetOffset +
        kAndroidTopOffset,
    marginBottom: 0,
    marginLeft: kMapUiPadding,
    marginRight: 0);

final ScaleBarSettings kPostDetailsScaleBarSettings = ScaleBarSettings(
    isMetricUnits: true,
    position: OrnamentPosition.TOP_LEFT,
    marginTop: kMapUiPadding,
    marginBottom: 0,
    marginLeft: kMapUiPadding,
    marginRight: 0);

final ScaleBarSettings kDefaultScaleBarSettings = ScaleBarSettings(
    isMetricUnits: true,
    position: OrnamentPosition.TOP_LEFT,
    marginTop: kMapUiTopOffset + kAndroidTopOffset * 4,
    marginBottom: 0,
    marginLeft: kMapUiPadding,
    marginRight: 0);

final AttributionSettings kDefaultAttributionSettings = AttributionSettings(
    position: OrnamentPosition.BOTTOM_LEFT,
    marginTop: 0,
    marginBottom: kAttributionBottomOffset,
    marginLeft: kAttributionLeftOffset,
    marginRight: 0);

final LogoSettings kDefaultLogoSettings = LogoSettings(
    position: OrnamentPosition.BOTTOM_LEFT,
    marginTop: 0,
    marginBottom: kAttributionBottomOffset,
    marginLeft: kLogoLeftOffset,
    marginRight: 0);

enum ViewMode {
  search,
  directions,
  parks,
  shuffle,
  navigation
}
