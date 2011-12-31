lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'wildcloud/keeper/version'

Gem::Specification.new do |s|
  s.name        = 'wildcloud-keeper'
  s.version     = Wildcloud::Keeper::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ['Marek Jelen']
  s.email       = ['marek@jelen.biz']
  s.homepage    = 'http://github.com/wildcloud'
  s.summary     = 'Keeper is responsible for managing applications on nodes.'
  s.description = 'Keeper deploys instances, starts and stops virtual machines'
  s.license     = 'Apache2'

  s.required_rubygems_version = '>= 1.3.6'

  s.add_dependency 'amqp', '0.8.4'
  s.add_dependency 'json', '1.6.4'
  s.add_dependency 'wildcloud-logger', '0.0.1'

  s.files        = Dir.glob('{bin,lib}/**/*') + %w(LICENSE README.md CHANGELOG.md)
  s.executables = %w(wildcloud-keeper)
  s.require_path = 'lib'
end