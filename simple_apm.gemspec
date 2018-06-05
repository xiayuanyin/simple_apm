$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "simple_apm/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "simple_apm"
  s.version     = SimpleApm::VERSION
  s.authors     = ["yuanyin.xia"]
  s.email       = ["xiayuanyin@qq.com"]
  s.homepage    = "https://github.com/xiayuanyin/simple_apm"
  s.summary     = "xyy: Simple Rails Apm"
  s.description = "xyy: Simple Apm View for rails using redis."
  s.license     = "MIT"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]

  s.add_dependency 'rails', '~> 4.2'
  s.add_dependency 'redis-namespace',  '~> 1.5'
  s.add_dependency 'callsite',  '~> 0.0'
end
