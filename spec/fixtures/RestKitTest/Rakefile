$:.unshift("/Library/RubyMotion/lib")
require 'motion/project'

if File.exist?(File.expand_path('../../../../lib/motion/project/cocoapods.rb', __FILE__))
  $:.unshift(File.expand_path('../../../../lib', __FILE__))
else
  require 'rubygems'
end
require 'motion-cocoapods'

Motion::Project::App.setup do |app|
  # Use `rake config' to see complete project settings.
  app.name = 'RestKitTest'
  app.pods do
    dependency 'RestKit/Network'
    # This is because the source of RestKit 0.10.0 has import statements that
    # depend on modules that might not be required, like in this case.
    dependency 'RestKit/UI'
    dependency 'RestKit/ObjectMapping'
    dependency 'RestKit/ObjectMapping/CoreData'
  end
end
