#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint feelback_ringtone.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'feelback_ringtone'
  s.version          = '0.0.1'
  s.summary          = 'Native singleton call ringtone manager for FeelBack'
  s.description      = <<-DESC
Native singleton call ringtone manager for FeelBack
                       DESC
  s.homepage         = 'http://feelback.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'FeelBack' => 'admin@feelback.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
