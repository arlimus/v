spec = Gem::Specification.new do |s|
  s.name = 'v'
  s.version = '1.4'
  s.platform = Gem::Platform::RUBY
  s.summary = "view anything from console"
  s.description = s.summary
  s.author = "Dominik Richter"
  s.email = "dominik.richter@googlemail.com"

  s.add_dependency "trollop"
  s.add_dependency "parseconfig"
  s.add_dependency "zlog"

  s.files = `git ls-files`.split("\n")
  s.executables = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end
