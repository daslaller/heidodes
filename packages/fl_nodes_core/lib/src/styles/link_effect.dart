import 'package:flutter/material.dart';

/// Paint-time effect applied to a link on the active links tier.
///
/// Effects are driven by the controller's active-links ticker. Implementations
/// must paint only the given [path] and must not mutate graph data.
abstract interface class FlLinkEffect {
  void paint(
    Canvas canvas,
    Path path,
    Paint basePaint,
    double animationValue,
  );
}
