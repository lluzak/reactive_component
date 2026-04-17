# frozen_string_literal: true

require_relative 'lib/reactive_component/version'

Gem::Specification.new do |spec|
  spec.name = 'reactive_component'
  spec.version = ReactiveComponent::VERSION
  spec.authors = ['Przemyslaw Lusar']
  spec.email = ['lluzak@gmail.com']

  spec.summary = 'Reactive server-rendered components for Rails via ActionCable'
  spec.description = 'Build reactive, real-time UI components that automatically re-render ' \
                     'server-side when subscribed models change. Uses ViewComponent, Turbo ' \
                     'Streams, and ActionCable to keep your UI in sync without writing custom JavaScript.'
  spec.homepage = 'https://github.com/przymusiala/reactive_component'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/przymusiala/reactive_component'
  spec.metadata['changelog_uri'] = 'https://github.com/przymusiala/reactive_component/blob/main/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.chdir(__dir__) do
    Dir['{app,config,lib}/**/*', 'CHANGELOG.md', 'LICENSE.txt'].reject { |f| File.directory?(f) }
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'prism', '~> 1.0'
  spec.add_dependency 'rails', '>= 7.1', '< 9'
  spec.add_dependency 'ruby2js', '~> 5.1'
  spec.add_dependency 'turbo-rails', '~> 2.0'
  spec.add_dependency 'view_component', '>= 3.0', '< 5'
end
