import 'dart:async';

class AndroidTransientNoticeCoordinator {
  Timer? _timer;
  void Function()? _dismissCurrent;
  int _generation = 0;

  void replace({
    required void Function() dismiss,
    required Duration timeout,
  }) {
    _timer?.cancel();
    _dismissCurrent?.call();

    final generation = ++_generation;
    _dismissCurrent = dismiss;
    _timer = Timer(timeout, () {
      if (_generation != generation) return;
      _timer = null;
      _dismissCurrent = null;
      dismiss();
    });
  }
}
