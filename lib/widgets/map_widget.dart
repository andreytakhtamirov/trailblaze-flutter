import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:location/location.dart' as loc;
import 'package:trailblaze/data/instruction.dart';
import 'package:trailblaze/util/export_helper.dart';
import 'package:trailblaze/util/format_helper.dart';
import 'package:trailblaze/widgets/map/directions_widget.dart';
import 'package:trailblaze/widgets/map/panels/navigation_panel.dart';
import 'package:turf/turf.dart' as turf;
import 'package:dartz/dartz.dart' as dartz;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbm;
import 'package:mapbox_search/mapbox_search.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:trailblaze/constants/map_constants.dart';
import 'package:trailblaze/constants/request_api_constants.dart';
import 'package:trailblaze/constants/ui_control_constants.dart';
import 'package:trailblaze/data/trailblaze_route.dart';
import 'package:trailblaze/extensions/mapbox_place_extension.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:trailblaze/managers/feature_manager.dart';
import 'package:trailblaze/screens/waypoint_edit_screen.dart';
import 'package:trailblaze/util/annotation_helper.dart';
import 'package:trailblaze/util/camera_helper.dart';
import 'package:trailblaze/util/firebase_helper.dart';
import 'package:trailblaze/util/ui_helper.dart';
import 'package:trailblaze/util/position_helper.dart';
import 'package:trailblaze/widgets/buttons/set_origin_button.dart';
import 'package:trailblaze/widgets/map/icon_button_small.dart';
import 'package:trailblaze/widgets/map/panels/features_panel.dart';
import 'package:trailblaze/widgets/map/panels/panel_widgets.dart';
import 'package:trailblaze/widgets/map/panels/place_info_panel.dart';
import 'package:trailblaze/widgets/map/panels/route_info_panel.dart';
import 'package:trailblaze/widgets/map/picked_locations_widget.dart';
import 'package:trailblaze/widgets/map/round_trip_controls_widget.dart';
import 'package:trailblaze/widgets/map_light_widget.dart';
import 'package:trailblaze/widgets/search_bar_widget.dart';
import 'package:trailblaze/data/feature.dart' as tb;

import '../data/transportation_mode.dart';
import '../requests/create_route.dart';
import '../widgets/map/map_style_selector_widget.dart';

class MapWidget extends StatefulWidget {
  final bool forceTopBottomPadding;
  final bool isInteractiveMap;
  final TrailblazeRoute? routeToDisplay;

  const MapWidget({
    super.key,
    // If this widget is hosted in a scaffold with a bottom navigation bar
    //  (and without a top app bar), we don't need to pad the top and bottom.
    this.forceTopBottomPadding = false,
    this.isInteractiveMap = true,
    this.routeToDisplay,
  });

  @override
  State<MapWidget> createState() => _MapWidgetState();
}

class _MapWidgetState extends State<MapWidget>
    with AutomaticKeepAliveClientMixin<MapWidget> {
  late mbm.MapboxMap _mapboxMap;
  loc.Location? location;
  MapBoxPlace? _selectedPlace;
  MapBoxPlace _startingLocation = MapBoxPlace(placeName: "My Location");
  String _selectedMode = kDefaultTransportationMode.value;
  num? _influenceValue;
  List<TrailblazeRoute> routesList = [];
  TrailblazeRoute? _selectedRoute;
  bool _fetchRouteOnNextUpdate = false;
  bool _isContentLoading = false;
  bool _mapStyleTouchContext = false;
  bool _routeControlsTouchContext = false;
  bool _manuallySelectedPlace = false;
  bool _pauseUiCallbacks = false;
  ViewMode _viewMode = ViewMode.search;
  ViewMode _previousViewMode = ViewMode.search;
  late Completer<void> _mapInitializedCompleter;
  AnnotationHelper? annotationHelper;
  List<tb.Feature>? _features;
  tb.Feature? _selectedFeature;
  double _fabHeight = kPanelFabHeight;
  double _panelOptionsHeight = kPanelFabHeight;
  double? _selectedDistanceMeters = kDefaultFeatureDistanceMeters;
  mbm.Position? _userLocation;
  final GlobalKey _topWidgetKey = GlobalKey();
  final GlobalKey _shareWidgetKey = GlobalKey();
  double _panelPosition = 0;

  bool _isOriginChanged = false;
  bool _isCameraLocked = false;
  bool _isFollowingLocation = false;
  bool _isAvoidAnnotationClicked = false;

  List<double>? _currentOriginCoordinates;
  List<double>? _nextOriginCoordinates;

  // Queried coordinates of features.
  List<double>? _featureQueriedCoordinates;

  final geocoding = GeoCoding(
    apiKey: kMapboxAccessToken,
    types: [PlaceType.address, PlaceType.poi],
    limit: null,
  );

  final PanelController _panelController = PanelController();
  final PageController _pageController = PageController(
    viewportFraction: 0.7,
    keepPage: false,
  );

  bool _isEditingAvoidArea = false;
  num _area = 0;
  bool _isAvoidActionUndoable = false;
  bool _isAvoidActionRedoable = false;
  int _numAvoidAnnotations = 0;

  @override
  void initState() {
    super.initState();
    _mapInitializedCompleter = Completer<void>();
    geo.Geolocator.getServiceStatusStream().listen((geo.ServiceStatus status) {
      // Listen for location permission granting.
      _getCurrentPosition();
    });
    _pageController.addListener(() {
      if (_pauseUiCallbacks ||
          _pageController.page == null ||
          _viewMode == ViewMode.directions) {
        return;
      }
      _onScrollChanged(_pageController.page!);
    });

    if (widget.routeToDisplay != null) {
      if (Platform.isAndroid) {
        Future.delayed(const Duration(milliseconds: 50), () {
          _mapInitializedCompleter.future.then((value) {
            _loadRouteToDisplay();
          });
        });
      } else {
        _mapInitializedCompleter.future.then((value) {
          _loadRouteToDisplay();
        });
      }
    }
  }

  void _enableLocationTracking() async {
    location = loc.Location();
    location?.enableBackgroundMode(enable: true);
    location?.onLocationChanged.listen((event) async {
      if (!_isFollowingLocation) {
        return;
      }
      final point = mbm.Point(
          coordinates: mbm.Position(event.longitude!, event.latitude!));
      final cameraOptions = mbm.CameraOptions(
          center: point, zoom: kNavigationMapZoom, bearing: event.heading);
      await _mapboxMap.easeTo(
          cameraOptions, mbm.MapAnimationOptions(duration: 1500));
    });
  }

  void _disableLocationTracking() {
    setState(() {
      _isFollowingLocation = false;
    });
    location?.enableBackgroundMode(enable: false);
    location?.onLocationChanged.listen(null);
  }

  void _loadRouteToDisplay() async {
    await _setViewMode(ViewMode.directions);

    final route = widget.routeToDisplay!;
    await _drawRoute(route);
    routesList.add(route);

    setState(() {
      _selectedRoute = route;
    });

    Future.delayed(const Duration(milliseconds: 20), () {
      if (_selectedRoute != null) {
        _flyToRoute(_selectedRoute!, isAnimated: false);
      }
    });

    _setMapControlSettings();
  }

  _onMapCreated(mbm.MapboxMap mapboxMap) async {
    setState(() {
      _mapboxMap = mapboxMap;
    });
    if (widget.isInteractiveMap) {
      // Only fly to user location if interactive
      await _goToUserLocation(isAnimated: false);
    }
    _showUserLocationPuck();
    _setMapControlSettings();

    final camera = await _mapboxMap.getCameraState();
    setState(() {
      _currentOriginCoordinates = [
        camera.center.coordinates.lng.toDouble(),
        camera.center.coordinates.lat.toDouble()
      ];
    });

    final pointAnnotationManager = await mapboxMap.annotations
        .createPointAnnotationManager(id: 'point-layer');
    final circleAnnotationManager = await mapboxMap.annotations
        .createCircleAnnotationManager(
            id: 'circle-layer', below: 'point-layer');
    final avoidAreaAnnotationManager = await mapboxMap.annotations
        .createCircleAnnotationManager(id: 'avoid-layer');
    final polygonAnnotationManager = await mapboxMap.annotations
        .createPolygonAnnotationManager(id: 'poly-layer', below: 'avoid-layer');
    annotationHelper = AnnotationHelper(
      pointAnnotationManager,
      circleAnnotationManager,
      avoidAreaAnnotationManager,
      polygonAnnotationManager,
      () {
        setState(() {
          _isAvoidAnnotationClicked = true;
        });
      },
    );

    _mapInitializedCompleter.complete();
  }

  void _setSelectedFeature(tb.Feature selectedFeature,
      {bool skipFlyToFeature = false}) {
    final f = selectedFeature;
    MapBoxPlace place = MapBoxPlace(
      placeName: f.tags['name'],
      center: [f.center['lon'], f.center['lat']],
    );

    if (!skipFlyToFeature) {
      _onSelectPlace(place);
    } else {
      setState(() {
        _selectedPlace = place;
      });
    }

    setState(() {
      _selectedFeature = selectedFeature;
    });

    _onSelectedFeatureChanged(selectedFeature);
  }

  void _onFeaturePageChanged(int index) {
    if (_pauseUiCallbacks) {
      return;
    }

    if (_features != null) {
      _setSelectedFeature(_features![index], skipFlyToFeature: true);
    }
  }

  void _onScrollChanged(double pageScrollProgress) async {
    if (_pauseUiCallbacks || _features == null || _features!.isEmpty) {
      return;
    }

    final currentFeature = _features![pageScrollProgress.floor()];
    final nextFeature = _features![pageScrollProgress.ceil()];

    final currentCameraCenter = mbm.Position(
        currentFeature.center['lon'], currentFeature.center['lat']);
    final nextCameraCenter =
        mbm.Position(nextFeature.center['lon'], nextFeature.center['lat']);

    final change = pageScrollProgress - pageScrollProgress.floor();
    final newCenter = CameraHelper.interpolatePoints(
        currentCameraCenter, nextCameraCenter, change);

    final cameraState = await _mapboxMap.getCameraState();
    final camera = await _getCameraOptions();
    final cameraOptions = mbm.CameraOptions(
      zoom: cameraState.zoom < 10 || cameraState.zoom > 14
          ? kDefaultCameraState.zoom
          : cameraState.zoom,
      center: mbm.Point(coordinates: newCenter),
      bearing: cameraState.bearing,
      padding: camera.padding,
      pitch: cameraState.pitch,
    );

    _mapFlyToOptions(cameraOptions, isAnimated: false);
  }

  void _onSelectedFeatureChanged(tb.Feature? oldFeature) async {
    await annotationHelper?.deletePointAnnotations();

    if (annotationHelper != null &&
        annotationHelper!.circleAnnotations.isEmpty) {
      await _updateFeatures();
    }

    final f = _selectedFeature;
    if (f != null) {
      if (oldFeature != null) {
        annotationHelper?.deletePointAnnotations();
      }

      // Fly to place after map is fully initialized to not interfere with animations.
      _mapInitializedCompleter.future.then((_) {
        annotationHelper?.drawSingleAnnotation(
            mbm.Position(f.center['lon'], f.center['lat']));
      });
    }
  }

  Future<void> _updateFeatures() async {
    if (_features == null) return;

    final List<mbm.Point> coordinatesList = [];
    for (var f in _features!) {
      coordinatesList.add(mbm.Point(
          coordinates: mbm.Position(f.center['lon'], f.center['lat'])));
    }

    annotationHelper?.drawCircleAnnotationMulti(coordinatesList);
    await _flyToFeatures(coordinatesList: coordinatesList);
  }

  Future<void> _flyToFeatures({List<mbm.Point>? coordinatesList}) async {
    await _clearCameraPadding();
    if (coordinatesList == null) {
      coordinatesList = [];
      for (var f in _features!) {
        coordinatesList.add(mbm.Point(
            coordinates: mbm.Position(f.center['lon'], f.center['lat'])));
      }
    }

    if (coordinatesList.length == 1) {
      // Only one feature so just fly to it.
      _flyToPlace(coordinatesList.first.coordinates);
      return;
    }

    final height = mounted ? MediaQuery.of(context).size.height : 0.0;
    final width = mounted ? MediaQuery.of(context).size.width : 0.0;
    final cameraForCoordinates = await CameraHelper.cameraOptionsForCoordinates(
      _mapboxMap,
      coordinatesList,
      _getCameraPadding(),
      height,
      width,
    );

    // Get SafeArea top padding (if any), for notched devices.
    cameraForCoordinates.padding?.top +=
        mounted ? MediaQuery.of(context).padding.top : 0;

    await _mapFlyToOptions(cameraForCoordinates);
  }

  void onManuallySelectFeature(tb.Feature feature) async {
    if (_features == null) return;

    setState(() {
      _pauseUiCallbacks = true;
    });
    final index = _features!.indexOf(feature);
    if (_pageController.positions.isNotEmpty) {
      await _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 100),
        curve: Curves.ease,
      );
    }
    await _togglePanel(true);
    _setSelectedFeature(feature);
    setState(() {
      _pauseUiCallbacks = false;
    });
  }

  void _onFeatureDistanceChanged(double distanceMeters) {
    setState(() {
      _selectedDistanceMeters = distanceMeters;
    });

    _loadFeatures(_selectedDistanceMeters!);
  }

  Future<void> _loadFeatures(double distanceMeters) async {
    if (_nextOriginCoordinates == null) {
      UiHelper.showSnackBar(context, "Could not find selected location.");
      return;
    }

    setState(() {
      _isContentLoading = true;
      _selectedDistanceMeters =
          (_selectedDistanceMeters ?? kDefaultFeatureDistanceMeters)
              .clamp(kMinFeatureDistanceMeters, kMaxFeatureDistanceMeters);
    });

    if (context.mounted) {
      final featuresPromise = FeatureManager.loadFeatures(
          context,
          (_selectedDistanceMeters ?? kDefaultFeatureDistanceMeters).toInt(),
          _nextOriginCoordinates!);

      setState(() {
        _features = null;
        _featureQueriedCoordinates = _nextOriginCoordinates;
      });

      final features = await featuresPromise;

      if (features.isEmpty) {
        setState(() {
          _features = [];
        });
      } else {
        setState(() {
          _features = features;
        });
        _setSelectedFeature(features.first, skipFlyToFeature: true);
      }

      await _updateFeatures();
    }

    setState(() {
      _isContentLoading = false;
    });
  }

  void _queryForRoundTrip({double? distanceMeters}) async {
    setState(() {
      _isOriginChanged = false;

      if (distanceMeters != null) {
        _selectedDistanceMeters = distanceMeters;
      }
    });
    _getDirectionsFromSettings();
  }

  void _setMapControlSettings() {
    Timer(const Duration(milliseconds: 300), () {
      if (_isEditingAvoidArea || _viewMode == ViewMode.navigation) {
        _mapboxMap.scaleBar
            .updateSettings(mbm.ScaleBarSettings(enabled: false));
        _mapboxMap.compass.updateSettings(mbm.CompassSettings(enabled: false));
        return;
      }

      double topOffset = _getTopOffset();

      final mbm.CompassSettings compassSettings;
      final mbm.ScaleBarSettings scaleBarSettings;

      if ((widget.isInteractiveMap &&
              _viewMode != ViewMode.shuffle &&
              _viewMode != ViewMode.directions) ||
          _viewMode == ViewMode.parks) {
        topOffset += kOptionsPillHeight;
      }

      if (!widget.forceTopBottomPadding) {
        compassSettings = mbm.CompassSettings(
            enabled: true,
            position: kDefaultCompassSettings.position,
            marginTop: kDefaultCompassSettings.marginTop! + topOffset,
            marginBottom: kDefaultCompassSettings.marginBottom,
            marginLeft: kDefaultCompassSettings.marginLeft,
            marginRight: kDefaultCompassSettings.marginRight);
        scaleBarSettings = mbm.ScaleBarSettings(
            enabled: true,
            isMetricUnits: kDefaultScaleBarSettings.isMetricUnits,
            position: kDefaultScaleBarSettings.position,
            marginTop: kDefaultScaleBarSettings.marginTop! + topOffset,
            marginBottom: kDefaultScaleBarSettings.marginBottom,
            marginLeft: kDefaultScaleBarSettings.marginLeft,
            marginRight: kDefaultScaleBarSettings.marginRight);
      } else {
        compassSettings = mbm.CompassSettings(
            enabled: true,
            position: kPostDetailsCompassSettings.position,
            marginTop: kPostDetailsCompassSettings.marginTop! + topOffset,
            marginBottom: kPostDetailsCompassSettings.marginBottom,
            marginLeft: kPostDetailsCompassSettings.marginLeft,
            marginRight: kPostDetailsCompassSettings.marginRight);
        scaleBarSettings = mbm.ScaleBarSettings(
            enabled: true,
            isMetricUnits: kPostDetailsScaleBarSettings.isMetricUnits,
            position: kPostDetailsScaleBarSettings.position,
            marginTop: kPostDetailsScaleBarSettings.marginTop! + topOffset,
            marginBottom: kPostDetailsScaleBarSettings.marginBottom,
            marginLeft: kPostDetailsScaleBarSettings.marginLeft,
            marginRight: kPostDetailsScaleBarSettings.marginRight);
      }

      final num bottomOffset = _getMinPanelHeight();

      final mbm.AttributionSettings kDefaultAttributionSettings =
          mbm.AttributionSettings(
              position: mbm.OrnamentPosition.BOTTOM_LEFT,
              marginTop: 0,
              marginBottom: kAttributionBottomOffset + bottomOffset,
              marginLeft: kAttributionLeftOffset,
              marginRight: 0);

      final mbm.LogoSettings kDefaultLogoSettings = mbm.LogoSettings(
          position: mbm.OrnamentPosition.BOTTOM_LEFT,
          marginTop: 0,
          marginBottom: kAttributionBottomOffset + bottomOffset,
          marginLeft: kLogoLeftOffset,
          marginRight: 0);

      _mapboxMap.compass.updateSettings(compassSettings);
      _mapboxMap.scaleBar.updateSettings(scaleBarSettings);
      _mapboxMap.attribution.updateSettings(kDefaultAttributionSettings);
      _mapboxMap.logo.updateSettings(kDefaultLogoSettings);
    });
  }

  double _getTopOffset() {
    double topOffset = 0;
    final double height = _topWidgetKey.currentContext != null
        ? (_topWidgetKey.currentContext?.findRenderObject() as RenderBox)
            .size
            .height
        : 0;

    if (_shouldShowDirectionsWidget() && _viewMode == ViewMode.search) {
      topOffset = kSearchBarHeight + 8;
    } else if (_viewMode == ViewMode.directions ||
        _viewMode == ViewMode.shuffle) {
      topOffset = height;
    }

    if (!widget.forceTopBottomPadding) {
      // Need to compensate for Android status bar.
      topOffset += kAndroidTopOffset;
    }

    return topOffset;
  }

  double _getBottomOffset({bool wantStatic = true}) {
    final double bottomOffset;
    if (_panelController.isAttached) {
      if (_isPanelBackdrop()) {
        bottomOffset = _getMinPanelHeight();
      } else if (!wantStatic) {
        // Non-static bottom offset (unstable when panel could be moving).
        bottomOffset = _panelController.panelPosition != 0
            ? (_getMaxPanelHeight() * _panelController.panelPosition)
            : _getMinPanelHeight();
      } else {
        // Static bottom offset (used when panel is moving, linear change).
        bottomOffset = _getMaxPanelHeight() * _panelController.panelPosition;
      }
    } else {
      bottomOffset = 0;
    }

    return bottomOffset;
  }

  Future<geo.Position?> _getCurrentPosition() async {
    geo.Position? position = await PositionHelper.getCurrentPosition(context);
    if (position == null) {
      return null;
    }

    MapBoxPlace myLocation = MapBoxPlace(
        placeName: "My Location",
        center: [position.longitude, position.latitude]);

    setState(() {
      _startingLocation = myLocation;
      _userLocation = mbm.Position(position.longitude, position.latitude);
    });

    return position;
  }

  Future<mbm.CameraOptions> _getCameraOptions(
      {mbm.Point? overrideCenter}) async {
    geo.Position? position = await _getCurrentPosition();

    mbm.Point center;

    if (overrideCenter == null) {
      if (position != null &&
          position.latitude != 0 &&
          position.longitude != 0) {
        center = mbm.Point(
            coordinates: mbm.Position(position.longitude, position.latitude));
      } else {
        center = kDefaultCameraState.center;
      }
    } else {
      center = overrideCenter;
    }

    return mbm.CameraOptions(
        zoom: kDefaultCameraState.zoom,
        center: center,
        bearing: kDefaultCameraState.bearing,
        padding: _getCameraPadding(),
        pitch: kDefaultCameraState.pitch);
  }

  mbm.MbxEdgeInsets _getCameraPadding() {
    final topOffset = _getTopOffset();
    double bottomOffset = _getBottomOffset();

    // Offset bottom by refresh button height.
    if (_viewMode == ViewMode.shuffle) {
      bottomOffset += kOptionsPillHeight;
    }

    return mbm.MbxEdgeInsets(
      top: (widget.isInteractiveMap ? 8 : 0) + topOffset,
      left: 0,
      bottom: bottomOffset,
      right: 0,
    );
  }

  void _updateDirectionsFabHeight(double pos) {
    setState(() {
      _fabHeight =
          pos * (_getMaxPanelHeight() - _getMinPanelHeight()) + kPanelFabHeight;
    });
  }

  void _onGpsButtonPressed() {
    setState(() {
      _isCameraLocked = false;
    });
    _goToUserLocation();
  }

  void _displayRoute(String profile, List<dynamic> waypoints) async {
    bool isRoundTrip = waypoints.length == 1;
    final double? distance = isRoundTrip ? _selectedDistanceMeters : null;

    await _removeRouteLayers();

    setState(() {
      _isContentLoading = true;
    });

    final dartz.Either<int, Map<String, dynamic>?> routeResponse;
    routeResponse = await createGraphhopperRoute(
      profile,
      waypoints,
      isRoundTrip: isRoundTrip,
      distanceMeters: distance,
      avoidArea: annotationHelper?.getAvoidPolygon(),
      influence: _influenceValue,
    );

    setState(() {
      _isContentLoading = false;
    });

    Map<String, dynamic>? routeData;

    routeResponse.fold(
      (error) => {
        if (error == 406)
          {
            UiHelper.showSnackBar(
                context, "Sorry, this region is not supported yet.")
          }
        else if (error == 422)
          {UiHelper.showSnackBar(context, "Requested points are too far away.")}
        else if (error == 404)
          {UiHelper.showSnackBar(context, "Failed to connect to the server.")}
        else
          {UiHelper.showSnackBar(context, "An unknown error occurred.")}
      },
      (data) => {routeData = data},
    );

    List<dynamic> routesJson = [];
    if ((routeData == null || routeData?['routes'] == null) &&
        routeData?['paths'] == null) {
      return;
    } else if (routeData?['routes'] != null) {
      routesJson = routeData!['routes'];
    } else {
      routesJson = routeData!['paths'];
    }

    for (var i = routesJson.length - 1; i >= 0; i--) {
      final routeJson = routesJson[i];

      bool isFirstRoute = i == 0;

      TrailblazeRoute route = TrailblazeRoute(
        kRouteSourceId + i.toString(),
        kRouteLayerId + i.toString(),
        routeJson,
        waypoints,
        routeData?['routeOptions'],
        isActive: isFirstRoute,
        isGraphhopperRoute: true,
      );

      _drawRoute(route);
      routesList.add(route);
    }

    setState(() {
      // The first route is selected initially.
      _selectedRoute = routesList.last;
    });

    if (_selectedRoute != null) {
      _flyToRoute(_selectedRoute!);
    }
    _setMapControlSettings();
  }

  void _flyToRoute(TrailblazeRoute route, {bool isAnimated = true}) async {
    await _clearCameraPadding();
    setState(() {
      _isCameraLocked = true;
    });

    final height = mounted ? MediaQuery.of(context).size.height : 0.0;
    final width = mounted ? MediaQuery.of(context).size.width : 0.0;

    final cameraForRoute = await CameraHelper.cameraOptionsForRoute(
      _mapboxMap,
      route,
      _getCameraPadding(),
      height,
      width,
      extraPadding: widget.forceTopBottomPadding,
    );
    await _mapFlyToOptions(cameraForRoute, isAnimated: isAnimated);
  }

  void _onFlyToRoute() async {
    Timer(const Duration(milliseconds: 300), () {
      if (_selectedRoute != null) {
        _flyToRoute(_selectedRoute!);
      }
    });
  }

  Future<void> _mapFlyToOptions(mbm.CameraOptions options,
      {bool isAnimated = true}) async {
    if (isAnimated) {
      await _mapboxMap.flyTo(options,
          mbm.MapAnimationOptions(duration: kMapFlyToDuration, startDelay: 0));
    } else {
      await _mapboxMap.setCamera(options);
    }
  }

  Future<void> _flyToPlace(mbm.Position coordinates) {
    return _mapFlyToOptions(
      mbm.CameraOptions(
          center: mbm.Point(coordinates: coordinates),
          padding: _getCameraPadding(),
          zoom: kDefaultCameraState.zoom + kPointSelectedCameraZoomOffset,
          bearing: kDefaultCameraState.bearing,
          pitch: kDefaultCameraState.pitch),
    );
  }

  void _setSelectedRoute(TrailblazeRoute route) async {
    setState(() {
      _selectedRoute = route;
    });

    final allRoutes = [...routesList];
    allRoutes.remove(_selectedRoute);

    if (_selectedRoute != null) {
      // Update all other routes (unselected grey)
      for (var route in allRoutes) {
        await _updateRouteSelected(route, false);
      }

      // Update selected route (red)
      await _updateRouteSelected(_selectedRoute!, true);
      _flyToRoute(_selectedRoute!);
    }
  }

  Future<void> _updateRouteSelected(
      TrailblazeRoute route, bool isSelected) async {
    // Make sure route is removed before we add it again.
    await _removeRouteLayer(route);
    route.setActive(isSelected);
    await _drawRoute(route);
  }

  Future<void> _drawRoute(TrailblazeRoute route) async {
    await annotationHelper?.deleteAllAnnotations();
    try {
      await _mapboxMap.style.addSource(route.geoJsonSource);
    } catch (e) {
      // Source might exist already
    }

    try {
      await _mapboxMap.style.removeStyleLayer(route.lineLayer.id);
    } catch (e) {
      // Route layer might have been removed already.
    }

    try {
      await _mapboxMap.style
          .addLayerAt(route.lineLayer, mbm.LayerPosition(below: "road-label"));
    } catch (e) {
      // "road-label" may not have been created yet or doesn't exist.
      await _mapboxMap.style.addLayer(route.lineLayer);
    }

    for (var i = 0; i < route.waypoints.length; i++) {
      final waypoint = route.waypoints[i];
      final mbp = MapBoxPlace.fromRawJson(waypoint);
      final point = mbm.Position(mbp.center?[0] ?? 0, mbp.center?[1] ?? 0);

      if (i == 0) {
        annotationHelper?.drawStartAnnotation(point);
      } else {
        annotationHelper?.drawSingleAnnotation(point);
      }
    }

    log(_selectedRoute!.coordinates!.toString());
    for (Instruction? i in _selectedRoute!.instructions!) {
      for (turf.Position p in i!.coordinates) {
        annotationHelper?.drawStartAnnotation(p);
      }
    }
  }

  Future<void> _removeRouteLayers() async {
    final copyList = [...routesList];
    routesList.clear();
    for (var route in copyList) {
      await _removeRouteLayer(route);
    }
  }

  Future<void> _removeRouteLayer(TrailblazeRoute route) async {
    try {
      if (await _mapboxMap.style.styleLayerExists(route.layerId)) {
        await _mapboxMap.style.removeStyleLayer(route.layerId);
      }
    } catch (e) {
      log('Exception removing route style layer: $e');
    }

    try {
      if (await _mapboxMap.style.styleSourceExists(route.sourceId)) {
        await _mapboxMap.style.removeStyleSource(route.sourceId);
      }
    } catch (e) {
      log('Exception removing route style source layer: $e');
    }
  }

  Future<void> _onExportRoute() async {
    if (_selectedRoute == null ||
        _selectedRoute!.coordinates == null ||
        _selectedRoute!.elevationMetrics == null) {
      UiHelper.showSnackBar(context, 'Unable to export route.',
          extraMarginBottom: true);
      return;
    }
    final coordinates = _selectedRoute!.coordinates!;
    final elevation = _selectedRoute!.elevationMetrics!;
    final gpx = ExportHelper.generateGpx(coordinates, elevation);

    final lastWaypoint =
        MapBoxPlace.fromRawJson(_selectedRoute!.waypoints.last);
    final box =
        (_shareWidgetKey.currentContext?.findRenderObject() as RenderBox);
    await ExportHelper.shareGpxFile(gpx, lastWaypoint.placeName ?? '',
        box.localToGlobal(Offset.zero) & box.size);
  }

  Future<void> _goToUserLocation({bool isAnimated = true}) async {
    geo.Position? position = await _getCurrentPosition();
    mbm.CameraOptions options = _cameraForUserPosition(position);
    _setNextOriginCoordinates(options);
    await _mapFlyToOptions(options, isAnimated: isAnimated);
  }

  mbm.CameraOptions _cameraForUserPosition(geo.Position? position) {
    final mbm.Point center;

    if (position != null && position.latitude != 0 && position.longitude != 0) {
      center = mbm.Point(
          coordinates: mbm.Position(position.longitude, position.latitude));
    } else {
      center = kDefaultCameraState.center;
    }
    return mbm.CameraOptions(
      center: center,
      padding: mbm.MbxEdgeInsets(
        top: 0,
        bottom: 0,
        left: 0,
        right: 0,
      ),
      zoom: _viewMode != ViewMode.navigation
          ? kDefaultCameraState.zoom
          : kNavigationMapZoom,
    );
  }

  void _setNextOriginCoordinates(mbm.CameraOptions options) {
    if (options.center != null) {
      setState(() {
        _nextOriginCoordinates = [
          options.center?.coordinates.lng.toDouble() ?? 0,
          options.center?.coordinates.lat.toDouble() ?? 0
        ];
      });
    }
  }

  void _showUserLocationPuck() async {
    final ByteData bytes = await rootBundle.load('assets/location-puck.png');
    final Uint8List list = bytes.buffer.asUint8List();

    _mapboxMap.location.updateSettings(mbm.LocationComponentSettings(
        locationPuck: mbm.LocationPuck(
            locationPuck2D: mbm.LocationPuck2D(topImage: list)),
        enabled: true));
  }

  void _onSelectPlace(MapBoxPlace? place,
      {bool isPlaceDataUpdate = false}) async {
    setState(() {
      _selectedPlace = place;
    });

    if (place == null) {
      _setMapControlSettings();
      _manuallySelectedPlace = false;
    }

    if (isPlaceDataUpdate) {
      // We don't need to redraw the annotation since
      // the only thing that changes is the place name.
      return;
    }

    if (place != null) {
      if (place.center != null) {
        setState(() {
          _nextOriginCoordinates = place.center?.cast<double>();
        });
      }

      _flyToPlace(mbm.Position(place.center?[0] ?? 0, place.center?[1] ?? 0));
      annotationHelper?.drawSingleAnnotation(
          mbm.Position(place.center?[0] ?? 0, place.center?[1] ?? 0));
    } else {
      annotationHelper?.deleteAllAnnotations();
    }
  }

  void _getDirectionsFromSettings() {
    setState(() {
      _isOriginChanged = false;
    });
    List<MapBoxPlace> waypoints = [];

    if (_viewMode == ViewMode.directions) {
      waypoints.insert(0, _startingLocation);
      if (_selectedPlace != null) {
        waypoints.add(_selectedPlace!);
      }
    } else if (_viewMode == ViewMode.shuffle) {
      waypoints.add(CameraHelper.getMapBoxPlaceFromLonLat(
          _currentOriginCoordinates,
          '${FormatHelper.formatDistance(_selectedDistanceMeters, noRemainder: true)} round trip'));
    }

    List<dynamic> waypointsJson = [];
    for (MapBoxPlace place in waypoints) {
      waypointsJson.add(place.toRawJsonWithNullCheck());
    }

    _displayRoute(_selectedMode, waypointsJson);
  }

  void _clearAvoidArea() {
    annotationHelper?.deleteAvoidArea();
    setState(() {
      _area = 0;
    });
    _onAvoidAnnotationsUpdate();
  }

  void _undoAvoidArea() async {
    annotationHelper?.undoLastAction();
    _onAvoidAnnotationsUpdate();
    _updateAvoidPoly();
  }

  void _redoAvoidArea() async {
    annotationHelper?.redoLastAction();
    _onAvoidAnnotationsUpdate();
    _updateAvoidPoly();
  }

  void _updateAvoidPoly() {
    if (annotationHelper != null &&
        annotationHelper!.avoidAnnotations.length > 2) {
      annotationHelper?.drawPolygonAnnotation();
    }
  }

  void _onAvoidAnnotationsUpdate() {
    setState(() {
      _numAvoidAnnotations = annotationHelper?.avoidAnnotations.length ?? 0;
      _isAvoidActionUndoable = annotationHelper?.canUndoAvoidAction() ?? false;
      _isAvoidActionRedoable = annotationHelper?.canRedoAvoidAction() ?? false;
    });

    final mbm.Polygon? poly = annotationHelper?.getAvoidPolygon();
    setState(() {
      if (poly != null) {
        _area = turf.area(poly) ?? 0; // Square km
      } else {
        _area = 0;
      }
    });
  }

  Future<void> _onMapTapListener(mbm.MapContentGestureContext context) async {
    final coordinate = context.point.coordinates;

    if (_isEditingAvoidArea) {
      Timer(const Duration(milliseconds: 10), () async {
        if (_isAvoidAnnotationClicked) {
          // Action already handled by annotation callback.
          setState(() {
            _isAvoidAnnotationClicked = false;
          });
        } else {
          await annotationHelper?.showAvoidAnnotation(coordinate);
        }

        _updateAvoidPoly();
        _onAvoidAnnotationsUpdate();
      });
      return;
    }

    if (_viewMode == ViewMode.navigation) {
      return;
    }

    if (_viewMode != ViewMode.directions) {
      await annotationHelper?.deletePointAnnotations();
    }

    if (_viewMode == ViewMode.directions) {
      TrailblazeRoute? selectedRoute;
      final cameraState = await _mapboxMap.getCameraState();

      selectedRoute = await AnnotationHelper.getRouteByClickProximity(
        routesList,
        coordinate.lng,
        coordinate.lat,
        cameraState.zoom,
      );

      // A route layer has been clicked.
      if (selectedRoute != null && selectedRoute != _selectedRoute) {
        _setSelectedRoute(selectedRoute);
        // We've handled the click event so
        //  we can avoid all other things.
        return;
      }

      // Block other map clicks when showing route.
      return;
    } else if (_viewMode == ViewMode.parks && _features != null) {
      final cameraState = await _mapboxMap.getCameraState();
      final closestFeature = await AnnotationHelper.getFeatureByClickProximity(
          _features!, coordinate.lng, coordinate.lat, cameraState.zoom);

      if (closestFeature != null) {
        onManuallySelectFeature(closestFeature);
        return;
      } else {
        await _togglePanel(false);
        _selectOriginOnMap(
            [coordinate.lng.toDouble(), coordinate.lat.toDouble()]);
        return;
      }
    } else if (_viewMode == ViewMode.shuffle) {
      _selectOriginOnMap(
          [coordinate.lng.toDouble(), coordinate.lat.toDouble()]);
      return;
    }

    MapBoxPlace place = MapBoxPlace(
        center: [coordinate.lng.toDouble(), coordinate.lat.toDouble()]);

    _onSelectPlace(place);

    Future<List<MapBoxPlace>?> futurePlaces = geocoding.getAddress(Location(
        lat: coordinate.lat.toDouble(), lng: coordinate.lng.toDouble()));

    futurePlaces.then((places) {
      setState(() {
        _manuallySelectedPlace = true;
      });
      String? placeName;
      if (places != null && places.isNotEmpty) {
        MapBoxPlace? place;
        for (MapBoxPlace p in places) {
          if (p.placeType.contains(PlaceType.poi)) {
            // Prioritize POI over address
            place = p;
            break;
          } else if (p.placeType.contains(PlaceType.address)) {
            place = p;
          }
        }

        if (place != null) {
          placeName = place.placeName!;
        }
      }

      placeName ??=
          "(${coordinate.lng.toStringAsFixed(4)}, ${coordinate.lat.toStringAsFixed(4)})";

      MapBoxPlace updatedPlace = MapBoxPlace(
          placeName: placeName,
          center: [coordinate.lng.toDouble(), coordinate.lat.toDouble()]);
      _onSelectPlace(updatedPlace, isPlaceDataUpdate: true);
      _setMapControlSettings();
    });
  }

  void _onMapScrollListener(mbm.MapContentGestureContext context) async {
    // Parks panel should stay open even if scrolling the camera
    if (_viewMode != ViewMode.parks) {
      _togglePanel(false);
    }

    if (_isCameraLocked) {
      setState(() {
        _isCameraLocked = false;
      });
    }

    if (_viewMode == ViewMode.navigation && _isFollowingLocation) {
      setState(() {
        _isFollowingLocation = false;
      });
    }
  }

  void _selectOriginOnMap(List<double> coordinates) {
    setState(() {
      _nextOriginCoordinates = coordinates;
      _isOriginChanged = true;
    });
    annotationHelper?.drawOriginAnnotation(
        mbm.Position(_nextOriginCoordinates![0], _nextOriginCoordinates![1]));
  }

  void _onDirectionsBackClicked() {
    if (_previousViewMode != ViewMode.navigation) {
      _setViewMode(_previousViewMode);
    } else {
      _setViewMode(ViewMode.search);
    }
    setState(() {
      _selectedRoute = null;
      _fabHeight = kPanelFabHeight;
    });
    _removeRouteLayers();

    _setOriginToUserLocation();
    annotationHelper?.deleteCircleAnnotations();
    annotationHelper?.clearAvoidActionHistory();
    _clearAvoidArea();
    _setMapControlSettings();
  }

  void _setOriginToUserLocation() async {
    final position = await _getCurrentPosition();
    if (position != null) {
      setState(() {
        _currentOriginCoordinates = [position.longitude, position.latitude];
      });
    }
  }

  void _onRouteSettingsChanged(
      TransportationMode mode, num? influenceValue, bool isSilent) {
    setState(() {
      _selectedMode = mode.value;
      _influenceValue = influenceValue;
      _routeControlsTouchContext = false;
    });

    if (!isSilent || _fetchRouteOnNextUpdate) {
      if (_fetchRouteOnNextUpdate) {
        setState(() {
          _fetchRouteOnNextUpdate = false;
        });
      }
      _getDirectionsFromSettings();
    }
  }

  Future<void> _showEditDirectionsScreen() async {
    FirebaseHelper.logScreen("EditDirections");
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WaypointEditScreen(
          startingLocation: _startingLocation,
          endingLocation: _selectedPlace,
          waypoints: const [],
        ),
      ),
    );

    if (result == null) {
      return;
    }

    //final List<dynamic> waypoints = result['waypoints']; TODO not implemented
    final MapBoxPlace startingLocation = result['startingLocation'];
    final MapBoxPlace endingLocation = result['endingLocation'];

    setState(() {
      _startingLocation = startingLocation;
    });

    annotationHelper?.deleteAllAnnotations();
    _onSelectPlace(endingLocation);

    setState(() {
      _fetchRouteOnNextUpdate = true;
    });
  }

  void _onStyleChanged(String newStyleId) async {
    setState(() {
      _mapStyleTouchContext = false;
    });

    String styleUri = '$kMapStyleUriPrefix/$newStyleId';

    if (await _mapboxMap.style.getStyleURI() == styleUri) {
      // Don't update if nothing changed.
      return;
    }

    await _mapboxMap.style.setStyleURI(styleUri);

    // Redraw routes to show them on top of the new style.
    for (var route in routesList) {
      if (route == _selectedRoute) {
        continue;
      }

      await _removeRouteLayer(route);
      _drawRoute(route);
    }

    if (_selectedRoute != null) {
      await _removeRouteLayer(_selectedRoute!);
      _drawRoute(_selectedRoute!);
    }
  }

  void _onTapOutsideMapStyle(PointerDownEvent event) {
    setState(() {
      _mapStyleTouchContext = false;
    });
  }

  void _onTapInsideMapStyle(PointerDownEvent event) {
    setState(() {
      _mapStyleTouchContext = true;
    });
  }

  void _onCollapseRouteControls() {
    setState(() {
      _routeControlsTouchContext = false;
    });
  }

  void _onExpandRouteControls() {
    setState(() {
      _routeControlsTouchContext = true;
    });
  }

  void _onDirectionsClicked() async {
    await _togglePanel(false);
    await _setViewMode(ViewMode.directions);

    if (_selectedMode == TransportationMode.none.value) {
      _onExpandRouteControls();
      return;
    }

    _getDirectionsFromSettings();
  }

  void _onMapOriginAction(bool isUpdate) {
    if (isUpdate) {
      setState(() {
        _currentOriginCoordinates = _nextOriginCoordinates;
        _isOriginChanged = false;
      });

      if (_viewMode == ViewMode.shuffle) {
        _queryForRoundTrip();
      } else if (_viewMode == ViewMode.parks) {
        _loadFeatures(_selectedDistanceMeters!);
      }
    } else {
      setState(() {
        annotationHelper?.deleteOriginAnnotation();
        _isOriginChanged = false;
      });
    }
  }

  void _setCameraPaddingForPanel(double pos) async {
    final cameraState = await _mapboxMap.getCameraState();
    if (context.mounted) {
      final bottomOffset = _getBottomOffset();

      final padding = mbm.MbxEdgeInsets(
        top: cameraState.padding.top,
        left: kDefaultCameraState.padding.left,
        bottom: kDefaultCameraState.padding.bottom + bottomOffset,
        right: kDefaultCameraState.padding.right,
      );
      _mapFlyToOptions(
          mbm.CameraOptions(
            zoom: cameraState.zoom,
            center: cameraState.center,
            bearing: cameraState.bearing,
            padding: padding,
            pitch: cameraState.pitch,
          ),
          isAnimated: false);
    }
  }

  Future<void> _toggleParksMode() async {
    if (_viewMode == ViewMode.parks) {
      await _setViewMode(ViewMode.search);
      await annotationHelper?.deleteAllAnnotations();
      _onSelectPlace(null);
    } else {
      FirebaseHelper.logScreen("NearbyParks");
      if (_features == null ||
          _features!.isEmpty ||
          _nextOriginCoordinates != _featureQueriedCoordinates) {
        await _loadFeatures(kDefaultFeatureDistanceMeters);
      }

      await _setViewMode(ViewMode.parks);
      setState(() {
        _pauseUiCallbacks = true;
      });
      _setSelectedFeature(_features!.first, skipFlyToFeature: true);
      await _togglePanel(true);
      setState(() {
        _pauseUiCallbacks = false;
      });
      await _flyToFeatures();
    }
  }

  Future<void> _toggleShuffleMode() async {
    if (_viewMode == ViewMode.shuffle) {
      await _setViewMode(ViewMode.search);
      await annotationHelper?.deleteAllAnnotations();
      _onSelectPlace(null);
    } else {
      FirebaseHelper.logScreen("Shuffle");
      await _setViewMode(ViewMode.shuffle);
      setState(() {
        _pauseUiCallbacks = true;
        if (_selectedPlace != null) {
          _currentOriginCoordinates = _selectedPlace!.center;
        }
      });

      _onSelectPlace(null);
      await _togglePanel(false);
      setState(() {
        _pauseUiCallbacks = false;
      });

      if (_selectedMode == TransportationMode.none.value) {
        setState(() {
          _selectedMode = TransportationMode.walking.value;
        });
      }
      _queryForRoundTrip();
    }
  }

  Future<void> _toggleNavigationMode() async {
    if (_viewMode == ViewMode.navigation) {
      _disableLocationTracking();
      await _setViewMode(ViewMode.directions);
    } else {
      _enableLocationTracking();
      await _setViewMode(ViewMode.navigation);
      setState(() {
        _isFollowingLocation = true;
      });
    }
  }

  void _onMapControlChanged(bool isEditingAvoidArea) {
    setState(() {
      _isEditingAvoidArea = isEditingAvoidArea;
    });

    if (_isEditingAvoidArea) {
      annotationHelper
          ?.showAvoidAnnotations(annotationHelper?.avoidAnnotations ?? []);
    } else {
      annotationHelper?.hideAvoidAnnotations();
      _getDirectionsFromSettings();
      setState(() {
        _routeControlsTouchContext = false;
      });
    }
  }

  Future<void> _togglePanel(bool isOpen) async {
    if (!_panelController.isAttached) {
      return;
    }

    if (isOpen && _panelController.isPanelClosed) {
      await _panelController.open();
    } else if (!isOpen && _panelController.isPanelOpen) {
      await _panelController.close();
    }
  }

  double _getMaxPanelHeight() {
    if (_viewMode == ViewMode.search && _selectedPlace != null) {
      return kPanelMaxHeight;
    } else if (_viewMode == ViewMode.search) {
      return 0;
    } else if (_viewMode == ViewMode.parks) {
      return kPanelFeaturesMaxHeight;
    } else {
      return kPanelRouteInfoMaxHeight;
    }
  }

  double _getMinPanelHeight() {
    if (_viewMode == ViewMode.search && _selectedPlace != null) {
      return kPanelMinContentHeight;
    } else if (_viewMode == ViewMode.search ||
        (_viewMode == ViewMode.directions && _selectedRoute == null)) {
      return 0;
    } else if ((_viewMode == ViewMode.directions ||
            _viewMode == ViewMode.shuffle) &&
        _selectedRoute != null) {
      return kPanelRouteInfoMinHeight;
    } else if (_viewMode == ViewMode.navigation) {
      return kPanelRouteInfoMinHeight;
    } else {
      return kPanelMinContentHeight;
    }
  }

  bool _isPanelBackdrop() {
    // In the directions view, the panel appears over
    //  top of the map thus not affecting padding.
    return _viewMode == ViewMode.directions ||
        _viewMode == ViewMode.shuffle ||
        _viewMode == ViewMode.navigation;
  }

  bool _shouldShowDirectionsWidget() {
    return widget.isInteractiveMap &&
        (_viewMode == ViewMode.search ||
            _manuallySelectedPlace ||
            _viewMode == ViewMode.directions) &&
        _viewMode != ViewMode.parks &&
        _viewMode != ViewMode.navigation;
  }

  Future<void> _clearCameraPadding() async {
    return await _mapboxMap.setCamera(
      mbm.CameraOptions(
        padding: mbm.MbxEdgeInsets(
          top: 0,
          left: 0,
          bottom: 0,
          right: 0,
        ),
      ),
    );
  }

  Future<void> _setViewMode(ViewMode newViewMode) async {
    setState(() {
      _previousViewMode = _viewMode;
      _viewMode = newViewMode;
    });

    if (_previousViewMode == ViewMode.parks) {
      annotationHelper?.deleteCircleAnnotations();
      setState(() {
        _pauseUiCallbacks = true;
      });
      await _togglePanel(false);
      setState(() {
        _pauseUiCallbacks = false;
      });
    } else if (_previousViewMode == ViewMode.directions ||
        _previousViewMode == ViewMode.shuffle) {
      await _removeRouteLayers();
    }

    if (_viewMode == ViewMode.parks) {
      _updateFeatures();
    } else if (_viewMode == ViewMode.navigation) {
      _drawRoute(_selectedRoute!);
      _goToUserLocation(isAnimated: true);
    }

    _updateDirectionsFabHeight(_panelController.panelPosition);
    _setMapControlSettings();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final bool isParksButtonVisible = (widget.isInteractiveMap &&
            _viewMode != ViewMode.shuffle &&
            _viewMode != ViewMode.navigation &&
            _viewMode != ViewMode.directions) ||
        _viewMode == ViewMode.parks;
    final bool isShuffleButtonVisible = (widget.isInteractiveMap &&
        _viewMode != ViewMode.shuffle &&
        _viewMode != ViewMode.navigation &&
        _viewMode != ViewMode.directions);
    final bool isDirectionsButtonVisible = _viewMode != ViewMode.directions &&
        _viewMode != ViewMode.shuffle &&
        _viewMode != ViewMode.navigation &&
        _selectedPlace != null &&
        !_isOriginChanged;
    final bool isRefreshButtonVisible =
        _viewMode == ViewMode.shuffle && !_isContentLoading;

    final bool shouldShowShuffleWidget =
        widget.isInteractiveMap && _viewMode == ViewMode.shuffle;

    final bool shouldShowNavigationWidget = widget.isInteractiveMap &&
        _viewMode == ViewMode.navigation &&
        _selectedRoute != null;

    final nonStaticBottomOffset = _getBottomOffset(wantStatic: false);

    final bool isPanelClosedAndAnimating = _panelController.isAttached &&
        _panelController.isPanelClosed &&
        !_panelController.isPanelAnimating;

    if (_mapInitializedCompleter.isCompleted) {
      _setMapControlSettings();
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Stack(
        children: [
          SlidingUpPanel(
            maxHeight: _getMaxPanelHeight(),
            minHeight: _getMinPanelHeight(),
            backdropEnabled: _isPanelBackdrop(),
            controller: _panelController,
            onPanelSlide: (double pos) {
              setState(() {
                _panelPosition = pos;
                _panelOptionsHeight =
                    pos * (_getMaxPanelHeight() - _getMinPanelHeight()) +
                        kPanelFabHeight;
              });
              if (_viewMode == ViewMode.directions ||
                  _viewMode == ViewMode.shuffle) {
                // If we're showing the directions view, no need to update
                //  the directions button or other elements.
                return;
              }

              if (!_pauseUiCallbacks) {
                // Don't interrupt changing camera.
                _setCameraPaddingForPanel(pos);
              }

              _updateDirectionsFabHeight(pos);
            },
            onPanelOpened: () {
              if (_pauseUiCallbacks ||
                  _viewMode != ViewMode.parks ||
                  _features == null) {
                return;
              }

              if (_selectedFeature != null) {
                onManuallySelectFeature(_selectedFeature!);
              } else {
                onManuallySelectFeature(_features!.first);
              }
            },
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16.0), bottom: Radius.zero),
            panel: GestureDetector(
              onTap: () {
                _togglePanel(true);
              },
              child: widget.forceTopBottomPadding
                  ? SafeArea(
                      child: Column(
                        children: _panels(isPanelClosedAndAnimating),
                      ),
                    )
                  : Column(
                      children: _panels(isPanelClosedAndAnimating),
                    ),
            ),
            body: Stack(
              children: [
                Scaffold(
                  body: MapLightWidget(
                    onMapCreated: _onMapCreated,
                    onMapTapListener: _onMapTapListener,
                    onScrollListener: _onMapScrollListener,
                  ),
                ),
                SafeArea(
                  child: Stack(
                    children: [
                      Positioned(
                        top: _getTopOffset(),
                        left: 0,
                        right: 0,
                        child: SingleChildScrollView(
                          padding: EdgeInsets.zero,
                          clipBehavior: Clip.none,
                          scrollDirection: Axis.horizontal,
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: ClipRRect(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                              child: Row(
                                children: <Widget>[
                                  Visibility(
                                    visible: isParksButtonVisible,
                                    child: IconButtonSmall(
                                      icon: _viewMode == ViewMode.parks
                                          ? Icons.close_rounded
                                          : Icons.forest_rounded,
                                      onTap: _toggleParksMode,
                                      text: 'Nearby Parks',
                                      backgroundColor:
                                          _viewMode == ViewMode.parks
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .secondary
                                              : Colors.white,
                                      foregroundColor:
                                          _viewMode == ViewMode.parks
                                              ? Colors.white
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .tertiary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Visibility(
                                    visible: isShuffleButtonVisible,
                                    child: IconButtonSmall(
                                      icon: _viewMode == ViewMode.shuffle
                                          ? Icons.close_rounded
                                          : Icons.route_outlined,
                                      onTap: _toggleShuffleMode,
                                      text: 'Route Explorer',
                                      backgroundColor:
                                          _viewMode == ViewMode.shuffle
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .secondary
                                              : Colors.white,
                                      foregroundColor:
                                          _viewMode == ViewMode.shuffle
                                              ? Colors.white
                                              : Colors.brown,
                                      isNew: true,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: (widget.forceTopBottomPadding == true)
                            ? 8
                            : kMapTopOffset,
                        left: 0,
                        right: 0,
                        child: Column(
                          children: [
                            if (_shouldShowDirectionsWidget())
                              _showDirectionsWidget()
                            else if (shouldShowShuffleWidget)
                              _showShuffleWidget()
                            else if (shouldShowNavigationWidget)
                              _showNavigationWidget()
                            else
                              const SizedBox(),
                            SizedBox(
                                height: isParksButtonVisible &&
                                        isShuffleButtonVisible
                                    ? 54
                                    : 0),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Visibility(
                                  visible: _isEditingAvoidArea,
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(32, 12, 0, 0),
                                    child: Row(
                                      children: [
                                        IconButtonSmall(
                                          icon: Icons.undo_rounded,
                                          onTap: _undoAvoidArea,
                                          isEnabled: _isAvoidActionUndoable,
                                        ),
                                        const SizedBox(width: 4),
                                        IconButtonSmall(
                                          icon: Icons.redo_rounded,
                                          onTap: _redoAvoidArea,
                                          isEnabled: _isAvoidActionRedoable,
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                    ),
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Visibility(
                                      visible: _isEditingAvoidArea,
                                      child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                              16, 8, 16, 0),
                                          child: IconButtonSmall(
                                            text: 'Clear Area',
                                            icon: Icons.delete_outline,
                                            onTap: _clearAvoidArea,
                                            isEnabled:
                                                _numAvoidAnnotations != 0,
                                            foregroundColor: Colors.red,
                                          )),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 8, 16, 0),
                                      child: TapRegion(
                                        onTapOutside: _onTapOutsideMapStyle,
                                        onTapInside: _onTapInsideMapStyle,
                                        child: MapStyleSelector(
                                          onStyleChanged: _onStyleChanged,
                                          hasTouchContext:
                                              _mapStyleTouchContext,
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 8, 16, 0),
                                      child: IconButtonSmall(
                                        icon: Icons.navigation_rounded,
                                        onTap: _onGpsButtonPressed,
                                      ),
                                    ),
                                    Visibility(
                                      visible:
                                          _viewMode == ViewMode.directions &&
                                              _selectedRoute != null &&
                                              !_isCameraLocked,
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            16, 8, 16, 0),
                                        child: IconButtonSmall(
                                          icon: Icons.crop_free_rounded,
                                          onTap: _onFlyToRoute,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_isContentLoading)
            Positioned(
              bottom: nonStaticBottomOffset + 8,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 200,
                  height: 70,
                  padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: LoadingAnimationWidget.staggeredDotsWave(
                      color: Theme.of(context).colorScheme.tertiary,
                      size: 50,
                    ),
                  ),
                ),
              ),
            )
          else if (_isOriginChanged && isPanelClosedAndAnimating)
            Positioned(
              bottom: nonStaticBottomOffset + 8,
              left: 0,
              right: 0,
              child: Center(
                child: SetOriginButton(
                  onAction: _onMapOriginAction,
                ),
              ),
            )
          else if (isRefreshButtonVisible && isPanelClosedAndAnimating)
            Positioned(
              bottom: nonStaticBottomOffset + 8,
              left: 0,
              right: 0,
              child: Center(
                child: IconButtonSmall(
                  text: "Shuffle",
                  icon: Icons.shuffle,
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  onTap: () {
                    _queryForRoundTrip();
                  },
                ),
              ),
            )
          else if (isDirectionsButtonVisible)
            Positioned(
              bottom: _fabHeight,
              right: 16,
              child: IconButtonSmall(
                text: 'Directions',
                icon: Icons.directions,
                iconFontSize: 28.0,
                textFontSize: 17,
                onTap: _onDirectionsClicked,
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          if (_selectedRoute != null && _viewMode == ViewMode.directions)
            Positioned(
              right: 4,
              bottom: _panelOptionsHeight - 10,
              child: PopupMenuButton(
                key: _shareWidgetKey,
                enabled: _selectedRoute?.coordinates?.length ==
                    _selectedRoute?.elevationMetrics?.length,
                icon: const Icon(Icons.ios_share),
                itemBuilder: (BuildContext context) {
                  return [
                    PopupMenuItem(
                      onTap: _onExportRoute,
                      child: const Text("Export to GPX"),
                    )
                  ];
                },
              ),
            ),
          if (_viewMode == ViewMode.navigation && !_isFollowingLocation)
            Positioned(
              left: 8,
              bottom: _panelOptionsHeight + 80,
              child: IconButtonSmall(
                icon: Icons.navigation_outlined,
                foregroundColor: Theme.of(context).colorScheme.primary,
                text: 'Follow',
                onTap: () {
                  _enableLocationTracking();
                  setState(() {
                    _isFollowingLocation = true;
                  });
                },
              ),
            ),
          if (_selectedRoute != null && _viewMode != ViewMode.navigation)
            Positioned(
              left: 4,
              bottom: _panelOptionsHeight - 10,
              child: IconButtonSmall(
                text: "Go",
                icon: Icons.navigation,
                onTap: _toggleNavigationMode,
              ),
            ),
        ],
      ),
    );
  }

  Widget _showDirectionsWidget() {
    return AnimatedContainer(
      key: _topWidgetKey,
      duration: const Duration(milliseconds: 300),
      child: AnimatedCrossFade(
        duration: const Duration(milliseconds: 300),
        crossFadeState: _viewMode == ViewMode.directions
            ? CrossFadeState.showSecond
            : CrossFadeState.showFirst,
        firstChild: PlaceSearchBar(
            onSelected: _onSelectPlace, selectedPlace: _selectedPlace),
        secondChild: TapRegion(
          onTapOutside: (_) {
            _onCollapseRouteControls();
          },
          child: PickedLocationsWidget(
            onBackClicked: _onDirectionsBackClicked,
            onOptionsChanged: _onRouteSettingsChanged,
            onMapControlChanged: _onMapControlChanged,
            onEditWaypoints: _showEditDirectionsScreen,
            onClearAvoidArea: _clearAvoidArea,
            onExpand: _onExpandRouteControls,
            onCollapse: _onCollapseRouteControls,
            startingLocation: _startingLocation,
            endingLocation: _selectedPlace,
            hasTouchContext: _routeControlsTouchContext,
            avoidArea: _area,
            waypoints: const [],
            selectedMode: getTransportationModeFromString(_selectedMode),
          ),
        ),
      ),
    );
  }

  Widget _showShuffleWidget() {
    return AnimatedContainer(
      key: _topWidgetKey,
      duration: const Duration(milliseconds: 300),
      child: RoundTripControlsWidget(
        onBackClicked: _onDirectionsBackClicked,
        onModeChanged: (TransportationMode mode, double? distance) {
          _onRouteSettingsChanged(mode, distance, false);
        },
        selectedMode: getTransportationModeFromString(_selectedMode),
        selectedDistanceMeters: _selectedDistanceMeters,
        onDistanceChanged: _queryForRoundTrip,
        center: _currentOriginCoordinates,
      ),
    );
  }

  Widget _showNavigationWidget() {
    return Padding(
      key: _topWidgetKey,
      padding: const EdgeInsets.all(8.0),
      child: DirectionsWidget(_selectedRoute!),
    );
  }

  List<Widget> _panels(bool panel) {
    List<Widget>? panels;

    switch (_viewMode) {
      case ViewMode.parks:
        panels = [
          PanelWidgets.panelGrabber(),
          FeaturesPanel(
            panelController: _panelController,
            pageController: _pageController,
            features: _features,
            userLocation: _userLocation,
            onFeaturePageChanged: _onFeaturePageChanged,
            selectedDistanceMeters: _selectedDistanceMeters,
            onDistanceChanged: _onFeatureDistanceChanged,
          )
        ];
        break;
      case ViewMode.navigation:
        panels = [
          PanelWidgets.panelGrabber(),
          NavigationPanel(route: _selectedRoute, onExit: _toggleNavigationMode),
        ];
      default:
        if (_selectedRoute != null) {
          panels = [
            PanelWidgets.panelGrabber(),
            RouteInfoPanel(
              route: _selectedRoute,
              hideSaveRoute: !widget.isInteractiveMap,
              panelHeight: _panelPosition,
            ),
          ];
        } else if (_selectedPlace != null) {
          panels = [
            PanelWidgets.panelGrabber(),
            PlaceInfoPanel(
              selectedPlace: _selectedPlace,
              userLocation: _userLocation,
            ),
          ];
        }
        break;
    }

    return panels ?? [];
  }

  @override
  bool get wantKeepAlive => true;
}
