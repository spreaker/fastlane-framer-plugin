# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'fastlane/plugin/framer/version'

Gem::Specification.new do |spec|
  spec.name          = 'fastlane-plugin-framer'
  spec.version       = Fastlane::Framer::VERSION
  spec.author        = %q{DrAL3X}
  spec.email         = %q{alessandro.calzavara@gmail.com}

  spec.summary       = %q{Create images combining app screenshots with templates to make nice pictures for the App Store}
  spec.homepage      = "https://github.com/spreaker/fastlane-framer-plugin"
  spec.license       = "MIT"

  spec.files         = Dir["lib/**/*"] + %w(README.md LICENSE)
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_dependency 'mini_magick', '~> 4.10.1' # To open, edit and export PSD files
  spec.add_dependency 'json'

  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rubocop'
  spec.add_development_dependency 'fastlane', '>= 1.100.0'
end
