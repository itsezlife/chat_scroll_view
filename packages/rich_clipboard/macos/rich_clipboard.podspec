Pod::Spec.new do |s|
  s.name             = 'rich_clipboard'
  s.version          = '0.1.0'
  s.summary          = 'Rich text on the system clipboard as plain text and HTML.'
  s.description      = 'The macOS side of rich_clipboard: one pasteboard item with the plain text and the HTML.'
  s.homepage         = 'https://github.com/itsezlife/chat_scroll_view'
  s.license          = { :type => 'Proprietary', :text => 'Part of chat_scroll_view.' }
  s.author           = { 'chat_scroll_view' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
