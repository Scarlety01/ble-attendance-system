class KalmanFilter {
  double q;
  double r;
  double x;
  double p;
  double k;

  KalmanFilter({
    this.q = 0.0001,
    this.r = 0.1,
    this.p = 1,
    this.x = 0,
    this.k = 0,
  });

  double update(double measurement) {
    p = p + q;
    k = p / (p + r);
    x = x + k * (measurement - x);
    p = (1 - k) * p;
    return x;
  }
}
