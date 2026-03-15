# frozen_string_literal: true

require_relative "lib/reactive_component/version"

Gem::Specification.new do |spec|
  spec.name = "reactive_component"
  spec.version = ReactiveComponent::VERSION
  spec.authors = ["Przemyslaw Lusar"]
  spec.email = ["lluzak@gmail.com"]

  spec.summary = "Reactive server-rendered components for Rails via ActionCable"
  spec.description = "Reactive server-rendered components for Rails via ActionCable"
  spec.homepage = "https://github.com/przymusiala/reactive_component"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/przymusiala/reactive_component"
  spec.metadata["changelog_uri"] = "https://github.com/przymusiala/reactive_component/blob/main/CHANGELOG.md"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "view_component"
  spec.add_dependency "turbo-rails"
  spec.add_dependency "ruby2js"
  spec.add_dependency "prism"
  spec.add_dependency "rails", ">= 7.1"
end
