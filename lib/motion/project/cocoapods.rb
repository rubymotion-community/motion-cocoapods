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

require 'xcodeproj'
require 'cocoapods'
require 'yaml'

module Motion::Project
  class Config
    variable :pods

    def pods(&block)
      @pods ||= Motion::Project::CocoaPods.new(self)
      if block
        # We run the update/install commands only if necessary.
        podfile_lock = Pod::Config.instance.project_lockfile
        podfile_changed = (!File.exist?(podfile_lock) or File.mtime(self.project_file) > File.mtime(podfile_lock))
        if podfile_changed and !ENV['COCOAPODS_NO_UPDATE']
          Pod::Command::Repo.new(Pod::Command::ARGV.new(["update"])).run
        end
        @pods.instance_eval(&block)
        @pods.install!
      end
      @pods
    end
  end

  class CocoaPods
    VERSION   = '1.2.1'
    PODS_ROOT = 'vendor/Pods'

    def initialize(config)
      @config = config

      @podfile = Pod::Podfile.new {}
      @podfile.platform :ios, config.deployment_target
      cp_config.podfile = @podfile

      if ENV['COCOAPODS_VERBOSE']
        cp_config.verbose = true
      else
        cp_config.silent = true
      end

      cp_config.integrate_targets = false
      cp_config.project_root = Pathname.new(File.expand_path(config.project_dir)) + 'vendor'
    end

    def pod(*name_and_version_requirements, &block)
      @podfile.pod(*name_and_version_requirements, &block)
    end

    # Deprecated.
    def dependency(*name_and_version_requirements, &block)
      @podfile.dependency(*name_and_version_requirements, &block)
    end

    def post_install(&block)
      @podfile.post_install(&block)
    end

    def pods_installer
      @installer ||= begin
        # This should move into a factory method in CocoaPods.
        sandbox = Pod::Sandbox.new(cp_config.project_pods_root)
        resolver = Pod::Resolver.new(@podfile, cp_config.lockfile, sandbox)
        resolver.update_mode = !!ENV['UPDATE']
        Pod::Installer.new(resolver)
      end
    end

    # For now we only support one Pods target, this will have to be expanded
    # once we work on more spec support.
    def install!
      if bridgesupport_file.exist? && cp_config.project_lockfile.exist?
        installed_pods_before = installed_pods
      end

      pods_installer.install!

      # Let RubyMotion re-generate the BridgeSupport file whenever the list of
      # installed pods changes.
      if bridgesupport_file.exist? && installed_pods_before &&
          installed_pods_before != installed_pods
        bridgesupport_file.delete
      end

      install_resources

      @config.vendor_project(PODS_ROOT, :xcode,
        :target => 'Pods',
        :headers_dir => 'Headers',
        :products => %w{ libPods.a }
      )

      if ldflags = pods_xcconfig.to_hash['OTHER_LDFLAGS']
        lib_search_paths = pods_xcconfig.to_hash['LIBRARY_SEARCH_PATHS'] || ""
        lib_search_paths.gsub!('$(PODS_ROOT)', "-L#{@config.project_dir}/#{PODS_ROOT}")

        framework_search_paths = pods_xcconfig.to_hash['FRAMEWORK_SEARCH_PATHS']
        if framework_search_paths
          framework_search_paths.scan(/\"([^\"]+)\"/) do |search_path|
            path = search_path.first.gsub!('$(PODS_ROOT)', "#{@config.project_dir}/#{PODS_ROOT}")
            @config.framework_search_paths << path
          end
        end

        @config.frameworks.concat(ldflags.scan(/-framework\s+([^\s]+)/).map { |m| m[0] })
        @config.frameworks.uniq!
        @config.libs.concat(ldflags.scan(/-l([^\s]+)/).map { |m|
          if lib_search_paths.length == 0 || File.exist?("/usr/lib/lib#{m[0]}.dylib")
            "/usr/lib/lib#{m[0]}.dylib"
          else
            "#{lib_search_paths} -all_load -l#{m[0]}"
          end
        })
        @config.libs.uniq!
      end
    end

    def cp_config
      Pod::Config.instance
    end

    def installed_pods
      YAML.load(cp_config.project_lockfile.read)['PODS']
    end

    def bridgesupport_file
      Pathname.new(@config.project_dir) + PODS_ROOT + 'Pods.bridgesupport'
    end

    def pods_xcconfig
      path = Pathname.new(@config.project_dir) + PODS_ROOT + 'Pods.xcconfig'
      Xcodeproj::Config.new(path)
    end

    def resources_dir
      Pathname.new(@config.project_dir) + PODS_ROOT + 'Resources'
    end

    def resources
      resources = []
      pods_resources_path = Pathname.new(@config.project_dir) + PODS_ROOT + "Pods-resources.sh"
      File.open(pods_resources_path) { |f|
        f.each_line do |line|
          if matched = line.match(/install_resource\s+'(.*)'/)
            resources << Pathname.new(@config.project_dir) + PODS_ROOT + matched[1]
          end
        end
      }
      resources
    end

    def install_resources
      FileUtils.mkdir_p(resources_dir)
      resources.each do |file|
        begin
          FileUtils.cp_r file, resources_dir
        rescue ArgumentError => exc
          unless exc.message =~ /same file/
            raise
          end
        end
      end
      @config.resources_dirs << resources_dir
    end

    def inspect
      ''
    end
  end
end
