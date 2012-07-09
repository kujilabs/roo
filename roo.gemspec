# -*- encoding: utf-8 -*-
require File.expand_path('../lib/roo/version', __FILE__)

Gem::Specification.new do |gem|
  gem.name          = "roo"
  gem.authors       = ["Thomas Preymesser"]
  gem.email         = ["thopre@gmail.com"]
  gem.description   = %q{Spreadsheet importer for ruby}
  gem.summary       = %q{Spreadsheet importer for ruby}
  gem.homepage      = "http://roo.rubyforge.org/"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  
  gem.require_paths = ["lib"]
  gem.version       = Roo::VERSION

  gem.add_dependency "choice", ">= 0.1.4"
  gem.add_dependency "google-spreadsheet-ruby", ">= 0.1.5"
  gem.add_dependency "nokogiri", ">= 1.5.0"
  gem.add_dependency "rubyzip", ">= 0.9.4"
  gem.add_dependency "spreadsheet", "> 0.6.4"
  gem.add_dependency "todonotes", ">= 0.1.0"
  
end
