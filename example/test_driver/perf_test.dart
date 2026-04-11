// Standard flutter drive boilerplate for collecting reportData from
// integration tests. Used when running:
//
//   flutter drive --driver=test_driver/perf_test.dart \
//       --target=integration_test/live2d_benchmark_test.dart --profile
//
// The driver receives reportData (populated by watchPerformance() in the
// test) and writes it to build/integration_response_data.json.

import 'package:integration_test/integration_test_driver_extended.dart'
    as driver;

Future<void> main() => driver.integrationDriver();
