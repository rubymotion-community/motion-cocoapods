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

task :clean do
  FileUtils.rm_rf 'pkg'
end

desc "Install dependencies needed for development"
task :bootstrap do
  sh "git submodule update --init"
  sh "bundle install"
end

desc "Run the specs"
task :spec do
  sh "bundle exec bacon #{FileList['spec/**/*_spec.rb'].join(' ')}"
end

desc "Run specs automatically"
task :kick do
  sh "bundle exec kicker -c -e 'rake spec'"
end

task :default => :spec
