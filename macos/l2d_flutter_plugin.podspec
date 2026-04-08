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

  # Vendor the prebuilt Cubism Core dynamic library for macOS
  s.vendored_libraries = 'Libraries/libLive2DCubismCore.dylib'
  s.preserve_paths = 'Libraries/**'

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/../Core/include"'
  }
  s.swift_version = '5.0'
end
