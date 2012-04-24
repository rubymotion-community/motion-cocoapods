require 'rake/gempackagetask'

Version = 1.0

GemSpec = Gem::Specification.new do |spec|
  spec.name = 'motion-cocoapods'
  spec.summary = 'CocoaPods integration for RubyMotion projects'
  spec.description = "motion-cocoapods allows RubyMotion projects to have access to the CocoaPods dependency manager."
  spec.author = 'Laurent Sansonetti'
  spec.email = 'lrz@hipbyte.com'
  spec.homepage = 'http://www.rubymotion.com'
  spec.version = Version

  files = []
  files << 'README.rdoc'
  files << 'LICENSE'
  files.concat(Dir.glob('lib/**/*.rb'))
  spec.files = files
end

Rake::GemPackageTask.new(GemSpec) do |pkg|
  pkg.need_zip = false
  pkg.need_tar = true
end

task :default => :gem

task :clean do
  FileUtils.rm_rf 'pkg'
end
