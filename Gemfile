# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

gem 'appraisal'
gem 'capybara'
gem 'cuprite'
gem 'importmap-rails'
# json 3.0 dropped the quirks_mode keyword ActiveSupport's encoder still passes
gem 'json', '< 3'
gem 'minitest', '~> 5.0'
gem 'propshaft'
gem 'puma'
gem 'rake', '~> 13.0'
gem 'redis'
gem 'sqlite3'
gem 'stimulus-rails'
gem 'turbo-rails'
gem 'view_component'

group :development do
  gem 'rubocop', '~> 1.90.0', require: false
  gem 'rubocop-minitest', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rails', require: false
end
