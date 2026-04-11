import 'package:flutter/material.dart';

/// Minimal launcher shell for the Live2D benchmark integration tests.
///
/// The integration tests at `integration_test/live2d_benchmark_test.dart`
/// replace the widget tree via `tester.pumpWidget()`, so this app only
/// needs to be launchable — it doesn't need to load models itself.
void main() {
  runApp(const MaterialApp(
    home: Scaffold(
      body: Center(
        child: Text(
          'Live2D Benchmark App\n\n'
          'Run benchmarks via:\n'
          '  flutter test integration_test/\n'
          'or:\n'
          '  flutter drive --driver=test_driver/perf_test.dart '
          '--target=integration_test/live2d_benchmark_test.dart',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  ));
}
