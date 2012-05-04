require 'rubygems'
require 'bundler/setup'

require 'pathname'
ROOT = Pathname.new(File.expand_path('../../', __FILE__))

$:.unshift("/Library/RubyMotion/lib")
$:.unshift((ROOT + 'lib').to_s)

require 'bacon'
Bacon.summary_at_exit

require 'rake'
require 'motion/project'

require 'cocoapods'
require 'motion-cocoapods'

require 'fileutils'
module SpecHelper
  def self.temporary_directory
    TemporaryDirectory.temporary_directory
  end

  module TemporaryDirectory
    def temporary_directory
      ROOT + 'tmp'
    end
    module_function :temporary_directory

    def setup_temporary_directory
      temporary_directory.mkpath
    end

    def teardown_temporary_directory
      temporary_directory.rmtree if temporary_directory.exist?
    end

    def self.extended(base)
      base.before do
        teardown_temporary_directory
        setup_temporary_directory
      end
    end
  end
end

require 'cocoapods/installer'
module Pod
  class Installer
    alias_method :original_dependent_specifications, :dependent_specifications
    # Here we override the `source' of the pod specifications to point to the integration fixtures.
    def dependent_specifications
      @dependent_specifications ||= original_dependent_specifications
      @dependent_specifications.each do |spec|
        unless spec.part_of_other_pod?
          source = spec.source
          source[:git] = (ROOT + "spec/fixtures/#{spec.name}").to_s
          spec.source = source
        end
      end
      @dependent_specifications
    end
  end
end
