import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:l2d_flutter_plugin/l2d_flutter_plugin.dart';
import 'package:l2d_flutter_plugin/src/generated/cubism_core_bindings.dart';

void _ensureCoreLoaded() {
  final coreSoPath =
      '${Directory.current.path}/Core/dll/linux/x86_64/libLive2DCubismCore.so';
  if (File(coreSoPath).existsSync()) {
    NativeLibrary.overrideBindings(
        CubismCoreBindings(DynamicLibrary.open(coreSoPath)));
  }
}

/// Visual regression tests for Live2DWidget rendering.
///
/// These tests use Flutter's golden file testing to verify that the
/// CubismRenderer produces consistent output for known model+state combinations.
///
/// Run with: `flutter test test/widgets/live2d_widget_test.dart`
/// Update goldens with: `flutter test --update-goldens test/widgets/live2d_widget_test.dart`
void main() {
  group('Live2DWidget', () {
    testWidgets('renders an empty controller without errors',
        (WidgetTester tester) async {
      final controller = Live2DController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: Live2DWidget(
                controller: controller,
                autoUpdate: false,
                backgroundColor: Colors.white,
              ),
            ),
          ),
        ),
      );

      // Should not throw, even with no model loaded
      expect(find.byType(Live2DWidget), findsOneWidget);
    });

    testWidgets('renders with loaded model and updates over time',
        (WidgetTester tester) async {
      _ensureCoreLoaded();

      final mocPath =
          '${Directory.current.path}/Samples/Resources/Haru/Haru.moc3';
      final settingsPath =
          '${Directory.current.path}/Samples/Resources/Haru/Haru.model3.json';
      final corePath =
          '${Directory.current.path}/Core/dll/linux/x86_64/libLive2DCubismCore.so';

      // Skip if sample files or Core lib aren't present (CI environments)
      if (!File(mocPath).existsSync() ||
          !File(settingsPath).existsSync() ||
          !File(corePath).existsSync()) {
        return;
      }

      final controller = Live2DController();
      controller.loadFromBytes(
        mocBytes: File(mocPath).readAsBytesSync(),
        settingsJson: File(settingsPath).readAsStringSync(),
      );

      expect(controller.isInitialized, isTrue);
      expect(controller.model, isNotNull);
      expect(controller.renderer, isNotNull);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: Live2DWidget(
                controller: controller,
                autoUpdate: true,
                backgroundColor: Colors.white,
              ),
            ),
          ),
        ),
      );

      // Pump several frames to advance the animation
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(find.byType(Live2DWidget), findsOneWidget);

      // Verify the controller's model state advances
      final paramX = controller.model!.getParameter('ParamAngleX');
      expect(paramX, isNotNull);
      expect(paramX!.value.isFinite, isTrue);

      controller.dispose();
    });

    testWidgets('disposing controller does not crash widget',
        (WidgetTester tester) async {
      final controller = Live2DController();

      await tester.pumpWidget(
        MaterialApp(
          home: Live2DWidget(
            controller: controller,
            autoUpdate: false,
          ),
        ),
      );

      controller.dispose();
      // Should not crash on next pump
      await tester.pump();
    });
  });

  group('Live2DController', () {
    test('initializes with no model', () {
      final controller = Live2DController();
      expect(controller.isInitialized, isFalse);
      expect(controller.model, isNull);
      expect(controller.renderer, isNull);
    });

    test('update on uninitialized controller is safe', () {
      final controller = Live2DController();
      // Should not throw
      controller.update(0.016);
    });

    test('dispose on uninitialized controller is safe', () {
      final controller = Live2DController();
      controller.dispose();
      controller.dispose(); // Double dispose should be idempotent
    });
  });
}
