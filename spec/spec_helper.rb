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
# Here we override the `source' of the pod specifications to point to the integration fixtures.
module Pod
  class Installer
    alias_method :original_specs_by_target, :specs_by_target
    def specs_by_target
      @specs_by_target ||= original_specs_by_target.tap do |hash|
        hash.values.flatten.each do |spec|
          next if spec.subspec?
          source = spec.source
          source[:git] = (ROOT + "spec/fixtures/#{spec.name}").to_s
          spec.source = source
        end
      end
    end
  end
end

