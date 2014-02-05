# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'tofulcrum/version'

Gem::Specification.new do |spec|
  spec.name          = "tofulcrum"
  spec.version       = Tofulcrum::VERSION
  spec.authors       = ["Zac McCormick"]
  spec.email         = ["zac.mccormick@gmail.com"]
  spec.description   = %q{Convert data to Fulcrum}
  spec.summary       = %q{Import data into Fulcrum from a CSV}
  spec.homepage      = "https://github.com/zhm/tofulcrum"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", "~> 0.7.6"
  spec.add_dependency "thor"
  spec.add_dependency "fulcrum"
  spec.add_dependency "axlsx"
  spec.add_dependency "roo"

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
end
