require './lib/opal-webpack-compile-server/version'

Gem::Specification.new do |s|
  s.name        = 'opal-webpack-compile-server'
  s.version     = OpalWebpackCompileServer::VERSION
  s.summary     = 'A compile server for opal-webpack-loader'
  s.description = 'Compile opal ruby from webpack'
  s.authors     = ['Jan Biedermann']
  s.email       = 'jan@kursator.de'
  s.files       = %w[lib/opal-webpack-compile-server/exe.rb lib/opal-webpack-compile-server/version.rb]
  s.executables << 'opal-webpack-compile-server'
  s.homepage    = 'https://github.com/janbiedermann/opal-webpack-compile-server'
  s.license     = 'MIT'

  s.add_dependency 'eventmachine', '~> 1.2.7'
  s.add_dependency 'oj', '~> 3.6.0'
  s.add_dependency 'opal', '>= 0.11.0'
end