import 'package:flutter/material.dart';
import 'package:trailblaze/constants/map_constants.dart';

class PanelWidgets {
  static Widget panelGrabber() {
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: kPanelGrabberHeight,
            height: 5,
            decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: const BorderRadius.all(Radius.circular(12.0))),
          ),
        ],
      ),
    );
  }
}