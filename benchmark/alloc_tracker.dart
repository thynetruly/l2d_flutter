// Allocation tracking wrapper that gracefully degrades without vm_service.
//
// Connects to the local VM service (when the benchmark process was launched
// with `--enable-vm-service`), snapshots the allocation profile before and
// after a timed block, and reports bytes allocated and per-class breakdowns.
//
// Two levels of detail:
//
//   AllocSample (basic) — whole-heap byte delta. Fast, low overhead.
//       Used by `run_all.dart --alloc` for every benchmark.
//
//   DetailedAllocSample (rich) — per-class instance/byte deltas via
//       AllocationProfile.members. Reports the top N allocating classes
//       (e.g. "CubismVector2: 750 instances, 12000 bytes") so you can
//       identify exactly which types are driving GC pressure without
//       opening DevTools Memory view manually. Used by `--devtools`.
//
// The design goal is: *no warning, no error* when VM service isn't available.
// Allocation tracking is opt-in via the `--alloc` or `--devtools` flags on
// run_all.dart, and benchmarks that rely on it bail out and emit null if the
// connection fails.

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// Result of a basic allocation sample taken around a block of work.
class AllocSample {
  /// Bytes allocated in new space + old space during the sampled window.
  final int bytes;

  /// Number of GC events observed during the allocation-tracking run.
  final int gcCount;

  const AllocSample(this.bytes, this.gcCount);
}

/// Per-class allocation delta from a detailed sample.
class ClassAllocDelta {
  final String className;
  final int instancesDelta;
  final int bytesDelta;

  const ClassAllocDelta(this.className, this.instancesDelta, this.bytesDelta);

  Map<String, Object> toJson() => {
        'className': className,
        'instancesDelta': instancesDelta,
        'bytesDelta': bytesDelta,
      };
}

/// Rich allocation sample with per-class breakdown. Used by `--devtools`.
class DetailedAllocSample {
  /// Total bytes allocated (same as [AllocSample.bytes]).
  final int totalBytes;

  /// Top allocating classes sorted by bytes descending, capped at
  /// [maxClasses] entries.
  final List<ClassAllocDelta> topClasses;

  const DetailedAllocSample(this.totalBytes, this.topClasses);

  List<Map<String, Object>> topClassesToJson() =>
      topClasses.map((c) => c.toJson()).toList();
}

/// Connects to the VM service (if available) and exposes samplers.
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

  /// Basic sample: whole-heap byte delta around [body].
  Future<AllocSample> sample(FutureOr<void> Function() body) async {
    await _service.getAllocationProfile(_isolateId, gc: true);
    final before = await _service.getAllocationProfile(_isolateId);
    await body();
    final after = await _service.getAllocationProfile(_isolateId);

    final bytesDelta = _sumHeapUsage(after) - _sumHeapUsage(before);
    return AllocSample(bytesDelta < 0 ? 0 : bytesDelta, 0);
  }

  /// Detailed sample: per-class instance/byte deltas around [body].
  ///
  /// Forces a GC before the "before" snapshot so accumulators start from
  /// a clean baseline. After [body] runs, diffs each class's accumulated
  /// instance count and byte total. Returns the top [maxClasses] classes
  /// by byte delta.
  Future<DetailedAllocSample> detailedSample(
    FutureOr<void> Function() body, {
    int maxClasses = 10,
  }) async {
    // Reset accumulators with a GC + fresh profile.
    await _service.getAllocationProfile(_isolateId, gc: true, reset: true);
    final before = await _service.getAllocationProfile(_isolateId);
    await body();
    final after = await _service.getAllocationProfile(_isolateId);

    final totalDelta = _sumHeapUsage(after) - _sumHeapUsage(before);

    // Build per-class deltas from the members lists.
    final beforeMap = _classStatsMap(before);
    final afterMap = _classStatsMap(after);

    final deltas = <ClassAllocDelta>[];
    for (final entry in afterMap.entries) {
      final className = entry.key;
      final afterStats = entry.value;
      final beforeStats = beforeMap[className];
      final instDelta = (afterStats.instances) -
          (beforeStats?.instances ?? 0);
      final byteDelta = (afterStats.bytes) -
          (beforeStats?.bytes ?? 0);
      if (instDelta > 0 || byteDelta > 0) {
        deltas.add(ClassAllocDelta(className, instDelta, byteDelta));
      }
    }

    // Sort by bytes descending, take top N.
    deltas.sort((a, b) => b.bytesDelta.compareTo(a.bytesDelta));
    final top = deltas.length > maxClasses
        ? deltas.sublist(0, maxClasses)
        : deltas;

    return DetailedAllocSample(totalDelta < 0 ? 0 : totalDelta, top);
  }

  int _sumHeapUsage(AllocationProfile profile) {
    final usage = profile.memoryUsage;
    if (usage == null) return 0;
    return (usage.heapUsage ?? 0) + (usage.externalUsage ?? 0);
  }

  Map<String, _ClassStats> _classStatsMap(AllocationProfile profile) {
    final map = <String, _ClassStats>{};
    final members = profile.members;
    if (members == null) return map;
    for (final member in members) {
      final name = member.classRef?.name;
      if (name == null || name.isEmpty) continue;
      map[name] = _ClassStats(
        member.instancesAccumulated ?? 0,
        member.accumulatedSize ?? 0,
      );
    }
    return map;
  }

  Future<void> dispose() async {
    try {
      await _service.dispose();
    } catch (_) {}
  }
}

class _ClassStats {
  final int instances;
  final int bytes;
  const _ClassStats(this.instances, this.bytes);
}

/// Convenience: print a warning to stderr explaining that alloc tracking
/// was requested but unavailable, then continue with null-allocation mode.
void warnAllocUnavailable() {
  stderr.writeln(
    '[benchmark] --alloc/--devtools requested but VM service not available. '
    'Relaunch with:\n'
    '  dart run --enable-vm-service --pause-isolates-on-exit=false '
    'benchmark/run_all.dart --alloc',
  );
}
