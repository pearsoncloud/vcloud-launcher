source 'http://rubygems.org'

gem 'vcloud-tools-tester', :path => '../vcloud-tools-tester'

gemspec

if ENV['VCLOUD_CORE_DEV_MASTER']
  gem 'vcloud-core', :git => 'git@github.com:alphagov/vcloud-core.git', :branch => 'master'
elsif ENV['VCLOUD_CORE_DEV_LOCAL']
  gem 'vcloud-core', :path => '../vcloud-core'
end
