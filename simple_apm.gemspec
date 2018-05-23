$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "simple_apm/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "simple_apm"
  s.version     = SimpleApm::VERSION
  s.authors     = ["yuanyin.xia"]
  s.email       = ["454536909@qq.com"]
  s.homepage    = "http://www.xiayuanyin.cn"
  s.summary     = "xyy: Summary of SimpleApm."
  s.description = "xyy: Description of SimpleApm."
  s.license     = "MIT"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]

  s.add_dependency 'rails'
  s.add_dependency 'redis'
  s.add_dependency 'hiredis'
  s.add_dependency 'redis-namespace'
end
