import 'package:flutter/widgets.dart';

/// Shared observer for root modal-route visibility.
///
/// Readers use it to pause foreground reading time while another route (AI,
/// search, note editor, system-style sheet) covers the reading surface.
final RouteObserver<ModalRoute<dynamic>> appRouteObserver =
    RouteObserver<ModalRoute<dynamic>>();
