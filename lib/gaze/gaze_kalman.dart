import "dart:math" as math;

class GazeKalman {
  GazeKalman({
    this.measurementVariance = 0.075,
    this.accelerationVariance = 1.0,
  });

  final double measurementVariance;
  final double accelerationVariance;


  final _x = _AxisKalman();
  final _y = _AxisKalman();
  DateTime? _lastUpdate;

  math.Point<double> update(math.Point<double> measurement, DateTime now) {
    if (_lastUpdate == null) {
      _lastUpdate = now;
      _x.initialize(measurement.x, measurementVariance);
      _y.initialize(measurement.y, measurementVariance);
      return measurement;
    }

    final dt = now.difference(_lastUpdate!).inMilliseconds / 1000.0;
    _lastUpdate = now;

    return math.Point(
      _x.update(measurement.x, dt, measurementVariance, accelerationVariance),
      _y.update(measurement.y, dt, measurementVariance, accelerationVariance),
    );
  }

  void reset() {
    _x.reset();
    _y.reset();
    _lastUpdate = null;
  }
}

class _AxisKalman {
  double position = 0.0;
  double velocity = 0.0;
  double _p00 = 0.0;
  double _p01 = 0.0;
  double _p11 = 0.0;

  bool initialized = false;

  void initialize(double position, double variance) {
    this.position = position;
    velocity = 0.0;
    _p00 = variance;
    _p01 = 0;
    _p11 = 1;

    initialized = true;
  }

  double update(
    double measurement,
    double dt,
    double measurementVariance,
    double accelerationVariance,
  ) {
    if (!initialized) {
      initialize(measurement, measurementVariance);
      return measurement;
    }

    dt = dt.clamp(0.001, 0.25);

    final dt2 = dt * dt;
    final dt3 = dt2 * dt;
    final dt4 = dt3 * dt;

    final predictedPosition = position + dt * velocity;
    final predictedVelocity = velocity;

    final pp00 = _p00 + 2 * dt * _p01 + dt2 * _p11 + accelerationVariance * dt4 / 4;
    final pp01 = _p01 + dt * _p11 + accelerationVariance * dt3 / 2;
    final pp11 = _p11 + accelerationVariance * dt2;


    final innovationVariance = _p00 + measurementVariance;
    final innovation = measurement - predictedPosition;
    final kPosition = pp00 / innovationVariance;
    final kVelocity = pp01 / innovationVariance;

    position = predictedPosition + kPosition * innovation;
    velocity = predictedVelocity + kVelocity * innovation;

    _p00 = (1 - kPosition) * pp00;
    _p01 = (1 - kPosition) * pp01;
    _p11 = pp11 - kVelocity * pp01;

    return position;
  }

  void reset() {
    initialized = false;
  }
}
