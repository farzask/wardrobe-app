import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Connectivity, used to choose between the network and the local cache.
///
/// Deliberately reports *reachability of a network*, not reachability of the backend. A phone on
/// hotel wifi with no route out will report online here and the request will fail — which is
/// correct behaviour: the request failing is what tells us, and guessing beforehand by pinging
/// would add a round trip to every action to be wrong slightly less often.
class ConnectivityService {
  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Future<bool> get isOnline async =>
      _isOnline(await _connectivity.checkConnectivity());

  Stream<bool> get onStatusChange =>
      _connectivity.onConnectivityChanged.map(_isOnline).distinct();

  bool _isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);
}
