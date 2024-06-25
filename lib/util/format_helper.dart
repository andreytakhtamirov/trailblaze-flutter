class FormatHelper {
  static String formatDuration(num? durationSeconds) {
    if (durationSeconds == null) {
      return "NaN";
    }

    int durationSecondsInt = durationSeconds.toInt();
    int hours = durationSecondsInt ~/ 3600;
    int minutes = (durationSecondsInt % 3600) ~/ 60;
    int seconds = durationSecondsInt % 60;

    String formattedDuration;
    if (hours > 0) {
      formattedDuration =
          "$hours hours ${minutes.toString().padLeft(2, '0')} minutes";
    } else if (minutes > 0) {
      formattedDuration = "$minutes minutes";
    } else {
      formattedDuration = "$seconds seconds";
    }

    return formattedDuration;
  }

  static String formatDistance(num? distance, {bool noRemainder = false}) {
    return "${(distance != null ? distance / 1000 : 0).toStringAsFixed(!noRemainder ? 2 : 0)} km";
  }

  static String formatDistancePrecise(num? distance,
      {bool noRemainder = false}) {
    if (distance == null || distance == 0) {
      return "0 m";
    }

    if (distance < 1000) {
      return "${distance.toStringAsFixed(0)} m";
    } else {
      return "${(distance / 1000).toStringAsFixed(!noRemainder ? 2 : 0)} km";
    }
  }

  static String formatSquareDistance(num? distance,
      {bool noRemainder = false}) {
    return "${(distance != null ? distance / 1e6 : 0).toStringAsFixed(!noRemainder ? 2 : 0)} km\u00B2";
  }

  static String formatLikesCount(int likes) {
    if (likes >= 1000000) {
      return "${(likes / 1000000).toStringAsFixed(1)}M";
    } else if (likes >= 1000) {
      return "${(likes / 1000).toStringAsFixed(1)}k";
    } else {
      return "$likes";
    }
  }
}
