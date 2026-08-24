#
# Run `pod lib lint emoji_data.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'emoji_data'
  s.version          = '0.0.1'
  s.summary          = 'Emoji catalog data and glyph support probes'
  s.description      = 'Emoji catalog data and glyph support probes'
  s.homepage         = 'https://github.com/chat_scroll_view/chat_scroll_view'
  s.license          = { :file => '../LICENSE', :type => 'MIT' }
  s.author           = { 'Chat Scroll View' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'emoji_data/Sources/emoji_data/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
