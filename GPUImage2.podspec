Pod::Spec.new do |s|

  s.name         = "GPUImage2"
  s.version      = "0.0.1"
  s.summary      = "An open source iOS framework for GPU-based image and video processing. Hush Fork."
  s.description  = <<-DESC
    Image Filtering & Processing & Camera stuff
                   DESC

  s.homepage     = "https://github.com/ShopHush/GPUImage2"
  s.license      = { :type => "BSD", :file => "License.txt" }
  # s.authors            = { 'Brad Larson' => 'contact@sunsetlakesoftware.com', "Brophy" => "john@shophush.com" }

  s.platform     = :ios
  s.ios.deployment_target = "9.0"

  s.source       = { :git => "git@github.com:ShopHush/GPUImage2.git", :tag => "#{s.version}" }


  s.source_files = 'framework/Source/**/*.{swift}'
  s.resources = 'framework/Source/Operations/Shaders/*.{fsh}'
  s.requires_arc = true
  s.xcconfig = { 'CLANG_MODULES_AUTOLINK' => 'YES', 'OTHER_SWIFT_FLAGS' => "$(inherited) -DGLES"}

  s.ios.exclude_files = 'framework/Source/Mac', 'framework/Source/Linux', 'framework/Source/Operations/Shaders/ConvertedShaders_GL.swift'
  s.frameworks   = ['OpenGLES', 'CoreMedia', 'QuartzCore', 'AVFoundation']
end
