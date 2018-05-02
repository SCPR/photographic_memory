Gem::Specification.new do |s|
  s.name           = "photographic_memory"
  s.version        = "0.0.0"
  s.date           = "2018-04-17"
  s.summary        = "Simple image processing and storage"
  s.description    = "Simple image processing and storage"
  s.authors        = ["Ten Bitcomb"]
  s.email          = "tenbitcomb@gmail.com"
  s.files          = ["lib/photographic_memory.rb"]
  s.homepage       = "http://github.com/scpr/photographic_memory"
  s.license        = "MIT"
  s.add_dependency "aws-sdk", "~> 2"
  s.add_dependency "mini_exiftool", "~> 2.8.0"
  s.add_dependency "rack", "~> 2.0.3"
  s.add_development_dependency "minitest", "~> 5.11.3"
end

