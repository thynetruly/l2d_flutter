Pod::Spec.new do |s|
  s.name             = 'l2d_flutter_plugin'
  s.version          = '0.0.1'
  s.summary          = 'Flutter FFI plugin for Live2D Cubism SDK.'
  s.description      = <<-DESC
Flutter FFI plugin providing Dart bindings to the Live2D Cubism Core C API.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'

  # Vendor the prebuilt Cubism Core static library for iOS
  s.vendored_libraries = 'Libraries/libLive2DCubismCore.a'
  s.preserve_paths = 'Libraries/**'

  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/../Core/include"',
    'OTHER_LDFLAGS' => '-force_load "$(PODS_TARGET_SRCROOT)/Libraries/libLive2DCubismCore.a"'
  }
  s.swift_version = '5.0'
end
