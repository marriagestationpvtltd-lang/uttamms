import 'package:flutter/material.dart';

const String noInternetRouteName = '/noInternet';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final AppRouteTracker appRouteTracker = AppRouteTracker();

class AppRouteTracker extends NavigatorObserver {
  Route<dynamic>? _currentRoute;

  Route<dynamic>? get currentRoute => _currentRoute;

  bool _isTrackableRoute(Route<dynamic>? route) {
    return route != null && route.settings.name != noInternetRouteName;
  }

  void _track(Route<dynamic>? route) {
    if (_isTrackableRoute(route)) {
      _currentRoute = route;
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _track(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _track(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _track(newRoute);
  }
}
