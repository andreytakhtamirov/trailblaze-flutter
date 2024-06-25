import 'package:flutter/material.dart';

enum Sign {
  uTurnUnknown(-98, Icons.u_turn_left),
  leftUTurn(-8, Icons.u_turn_left),
  keepLeft(-7, Icons.north_west),
  leaveRoundabout(-6, Icons.roundabout_left),
  sharpLeft(-3, Icons.turn_sharp_left_sharp),
  turnLeft(-2, Icons.turn_left),
  slightLeft(-1, Icons.turn_slight_left),
  continueStreet(0, Icons.straight),
  slightRight(1, Icons.turn_slight_right),
  turnRight(2, Icons.turn_right),
  sharpRight(3, Icons.turn_sharp_right),
  finish(4, Icons.flag_outlined),
  viaPoint(5, Icons.flag_circle),
  enterRoundabout(6, Icons.straight),
  keepRight(7, Icons.north_east),
  rightUTurn(8, Icons.u_turn_right),
  unknown(-100, Icons.question_mark);

  final int value;
  final IconData icon;

  static const List<Sign> signs = [
    uTurnUnknown,
    leftUTurn,
    keepLeft,
    leaveRoundabout,
    sharpLeft,
    turnLeft,
    slightLeft,
    continueStreet,
    slightRight,
    turnRight,
    sharpRight,
    finish,
    viaPoint,
    enterRoundabout,
    keepRight,
    rightUTurn,
    unknown,
  ];

  static Sign fromValue(int value) {
    return signs.firstWhere((sign) => sign.value == value,
        orElse: () => unknown);
  }

  const Sign(this.value, this.icon);
}
