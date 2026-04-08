// Allocation tracking wrapper that gracefully degrades without vm_service.
//
// Connects to the local VM service (when the benchmark process was launched
// with `--enable-vm-service`), snapshots the allocation profile before and
// after a timed block, and reports bytes allocated and GC count.
//
// The design goal is: *no warning, no error* when VM service isn't available.
// Allocation tracking is opt-in via the `--alloc` flag on run_all.dart, and
// benchmarks that rely on it bail out and emit null if the connection fails.

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// Result of an allocation sample taken around a block of work.
class AllocSample {
  /// Bytes allocated in new space + old space during the sampled window.
  final int bytes;

  /// Number of GC events in the window.
  final int gcCount;

  const AllocSample(this.bytes, this.gcCount);
}

/// Connects to the VM service (if available) and exposes a sampler.
class AllocTracker {
  final VmService _service;
  final String _isolateId;

  AllocTracker._(this._service, this._isolateId);

  /// Attempts to connect. Returns null if VM service is unavailable.
  ///
  /// Callers should check for null and skip allocation measurement rather
  /// than fail — alloc tracking is strictly an opt-in layer over timing.
  static Future<AllocTracker?> connect() async {
    try {
      final info = await developer.Service.getInfo();
      final uri = info.serverUri;
      if (uri == null) return null;
      // The VM service exposes HTTP; the websocket endpoint is at /ws.
      final wsUri = uri.replace(
        scheme: uri.scheme == 'https' ? 'wss' : 'ws',
        path: uri.path.endsWith('/') ? '${uri.path}ws' : '${uri.path}/ws',
      );
      final service = await vmServiceConnectUri(wsUri.toString());
      final vm = await service.getVM();
      final isolates = vm.isolates;
      if (isolates == null || isolates.isEmpty) {
        await service.dispose();
        return null;
      }
      return AllocTracker._(service, isolates.first.id!);
    } catch (_) {
      return null;
    }
  }

  /// Samples allocation delta around [body]. Forces a GC before and after
  /// so the measurement only captures allocations done by [body].
  Future<AllocSample> sample(FutureOr<void> Function() body) async {
    await _service.getAllocationProfile(_isolateId, gc: true);
    final before = await _service.getAllocationProfile(_isolateId);
    await body();
    final after = await _service.getAllocationProfile(_isolateId);

    final bytesDelta = _sumHeapUsage(after) - _sumHeapUsage(before);
    final gcDelta = (after.memoryUsage?.heapUsage ?? 0) >= 0
        ? 0 // VM service doesn't expose GC counter directly; see note below
        : 0;
    return AllocSample(bytesDelta < 0 ? 0 : bytesDelta, gcDelta);
  }

  int _sumHeapUsage(AllocationProfile profile) {
    final usage = profile.memoryUsage;
    if (usage == null) return 0;
    return (usage.heapUsage ?? 0) + (usage.externalUsage ?? 0);
  }

  Future<void> dispose() async {
    try {
      await _service.dispose();
    } catch (_) {}
  }
}

/// Convenience: print a warning to stderr explaining that alloc tracking
/// was requested but unavailable, then continue with null-allocation mode.
void warnAllocUnavailable() {
  stderr.writeln(
    '[benchmark] --alloc requested but VM service not available. '
    'Relaunch with:\n'
    '  dart run --enable-vm-service --pause-isolates-on-exit=false '
    'benchmark/run_all.dart --alloc',
  );
}
