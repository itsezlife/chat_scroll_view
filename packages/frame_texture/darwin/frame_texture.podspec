Pod::Spec.new do |s|
  s.name             = 'frame_texture'
  s.version          = '0.1.0'
  s.summary          = 'Textures a render worker writes frames into (ADR 043).'
  s.description      = 'The iOS and macOS texture host of frame_texture: a FlutterTexture per texture over a ring of IOSurface-backed CVPixelBuffers, with the C lock and post entry points the render workers call through FFI.'
  s.homepage         = 'https://github.com/itsezlife/chat_scroll_view'
  s.license          = { :type => 'Proprietary', :text => 'Part of chat_scroll_view.' }
  s.author           = { 'chat_scroll_view' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/FrameTexturePlugin.h'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'
  s.frameworks = 'CoreVideo'
  s.requires_arc = true
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
end
