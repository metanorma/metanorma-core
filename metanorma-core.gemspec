# coding: utf-8

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "metanorma/core/version"

Gem::Specification.new do |spec|
  spec.name          = "metanorma-core"
  spec.version       = Metanorma::Core::VERSION
  spec.authors       = ["Ribose Inc."]
  spec.email         = ["open.source@ribose.com"]

  spec.summary       = "Metanorma Core"
  spec.description   = <<~DESCRIPTION
    Core library for Metanorma processor registration and plugin dependencies
  DESCRIPTION

  spec.homepage      = "https://github.com/metanorma/metanorma-core"
  spec.license       = "BSD-2-Clause"
  spec.bindir        = "bin"
  spec.require_paths = ["lib"]
  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features|bin|.github)/}) \
    || f.match(%r{Rakefile|bin/rspec})
  end
  spec.required_ruby_version = Gem::Requirement.new(">= 3.1.0")

  spec.add_dependency "asciidoctor"
  spec.add_dependency "metanorma-taste", "~> 1.0.0"
  spec.add_dependency "nokogiri"

  spec.add_development_dependency "debug"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.6"
  spec.add_development_dependency "rubocop", "~> 1"
  spec.add_development_dependency "rubocop-performance"
  spec.add_development_dependency "simplecov", "~> 0.15"
  #spec.metadata["rubygems_mfa_required"] = "true"
end
