# Copyright (c) 2012, Laurent Sansonetti <lrz@hipbyte.com>
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

unless defined?(Motion::Project::Config)
  raise "This file must be required within a RubyMotion project Rakefile."
end

require 'cocoapods'

module Motion::Project
  class Config
    variable :pods

    def pods(&block)
      @pods ||= Motion::Project::CocoaPods.new(self)
      if block
        @pods.instance_eval(&block)
        @pods.install!
      end
      @pods
    end
  end

  class CocoaPods
    VERSION = '1.0.1'

    def initialize(config)
      @config = config
      @podfile = Pod::Podfile.new {}
      @podfile.platform :ios

      cp_config = Pod::Config.instance
      if ENV['COCOAPODS_VERBOSE']
        cp_config.verbose = true
      else
        cp_config.silent = true
      end
      cp_config.rootspec = @podfile if cp_config.respond_to?(:rootspec) # CocoaPods 0.5.x backward compatibility
      cp_config.integrate_targets = false if cp_config.respond_to?(:integrate_targets) # CocoaPods 0.6 forward compatibility
      cp_config.project_root = Pathname.new(config.project_dir) + 'vendor'
    end

    def dependency(*name_and_version_requirements, &block)
      @podfile.dependency(*name_and_version_requirements, &block)
    end

    def post_install(&block)
      @podfile.post_install(&block)
    end

    def pods_installer
      @installer ||= Pod::Installer.new(@podfile)
    end

    # For now we only support one Pods target, this will have to be expanded
    # once we work on more spec support.
    def install!
      pods_installer.install!

      @config.vendor_project('vendor/Pods', :xcode,
        :target => 'Pods',
        :headers_dir => 'Headers',
        :products => %w{ libPods.a }
      )

      xcconfig = @installer.target_installers.find do |target_installer|
        if target_installer.respond_to?(:definition)
          target_installer.definition.name == :default
        else
          # CocoaPods 0.6 forward compatibility
          target_installer.target_definition.name == :default
        end
      end.xcconfig

      if ldflags = xcconfig.to_hash['OTHER_LDFLAGS']
        @config.frameworks.concat(ldflags.scan(/-framework\s+([^\s]+)/).map { |m| m[0] })
        @config.frameworks.uniq!
        @config.libs.concat(ldflags.scan(/-l([^\s]+)/).map { |m| "/usr/lib/lib#{m[0]}.dylib" })
        @config.libs.uniq!
      end
    end
  end
end
