Pod::Spec.new do |spec|
  spec.name         = "FlatCircleTorus-utils"
  spec.version      = "1.1.5"
  spec.platform = :ios, "11.0"
  spec.summary      = "Retrieve user shares"
  spec.homepage     = "https://github.com/flatcircle/torus-utils-swift"
  spec.license      = { :type => 'BSD', :file => 'License.md' }
  spec.swift_version   = "5.0"
  spec.author       = { "Torus Labs" => "rathishubham017@gmail.com" }
  spec.module_name = "FlatCircleTorusUtils"
  spec.source       = { :git => "https://github.com/flatcircle/torus-utils-swift.git", :tag => spec.version }
  spec.source_files = "Sources/TorusUtils/*.{swift,json}","Sources/TorusUtils/**/*.{swift,json}"
  spec.dependency 'FlatCircleTorus-fetchNodeDetails', '~> 1.1.5'
  spec.dependency 'PromiseKit/Foundation', '~> 6.0'
  spec.dependency 'BestLogger', '~> 0.0.1'
  spec.pod_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64' }
  spec.user_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64' }
end
