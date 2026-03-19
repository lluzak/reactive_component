# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'minitest/test_task'
require 'rubocop/rake_task'

RuboCop::RakeTask.new

Minitest::TestTask.create do |t|
  t.test_globs = ['test/lib/**/*_test.rb', 'test/channels/**/*_test.rb']
end

namespace :test do
  desc 'Run JavaScript unit tests with Vitest'
  task :js do
    sh 'npx vitest run'
  end

  Minitest::TestTask.create(:system) do |t|
    t.test_globs = ['test/system/**/*_test.rb']
  end
end

task default: %i[test test:system test:js]
