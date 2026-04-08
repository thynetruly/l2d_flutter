/// Flutter FFI plugin for Live2D Cubism SDK.
///
/// Provides Dart bindings to the Cubism Core C API and Dart reimplementations
/// of the Cubism Framework (animation, physics, effects, rendering).
library;

export 'src/core/cubism_core.dart';
export 'src/core/cubism_moc.dart';
export 'src/core/cubism_model.dart';
export 'src/core/cubism_parameter.dart';
export 'src/core/cubism_part.dart';
export 'src/core/cubism_drawable.dart';
export 'src/core/cubism_canvas.dart';
export 'src/core/native_library.dart' show NativeLibrary;

// Framework
export 'src/framework/math/cubism_math.dart';
export 'src/framework/math/cubism_vector2.dart';
export 'src/framework/math/cubism_matrix44.dart';
export 'src/framework/math/cubism_model_matrix.dart';
export 'src/framework/math/cubism_view_matrix.dart';
export 'src/framework/id/cubism_id.dart';
export 'src/framework/id/cubism_default_parameter_id.dart';
export 'src/framework/cubism_model_setting_json.dart';
export 'src/framework/effect/cubism_eye_blink.dart';
export 'src/framework/effect/cubism_breath.dart';
export 'src/framework/effect/cubism_look.dart';
export 'src/framework/effect/cubism_pose.dart';
export 'src/framework/motion/cubism_motion.dart';
export 'src/framework/motion/cubism_motion_manager.dart';
export 'src/framework/motion/cubism_motion_queue_entry.dart';
export 'src/framework/motion/cubism_motion_queue_manager.dart';
export 'src/framework/motion/cubism_expression_motion.dart';
export 'src/framework/physics/cubism_physics.dart';
export 'src/framework/rendering/cubism_renderer.dart';

// Widgets
export 'src/widgets/live2d_widget.dart';
export 'src/widgets/live2d_controller.dart';
