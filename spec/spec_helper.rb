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

