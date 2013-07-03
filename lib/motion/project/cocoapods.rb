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
        @pods.instance_eval(&block)

        # We run the update/install commands only if necessary.
        cp_config = Pod::Config.instance
        analyzer = Pod::Installer::Analyzer.new(cp_config.sandbox, @pods.podfile, cp_config.lockfile)
        begin
          need_install = analyzer.needs_install?
        rescue
          need_install = true
        end
        @pods.install! if need_install
        @pods.link_project
      end
      @pods
    end
  end

  #---------------------------------------------------------------------------#

  class CocoaPods
    VERSION   = '1.3.4'
    PODS_ROOT = 'vendor/Pods'

    attr_accessor :podfile

    def initialize(config)
      @config = config

      @podfile = Pod::Podfile.new {}
      @podfile.platform((App.respond_to?(:template) ? App.template : :ios), config.deployment_target)
      cp_config.podfile = @podfile

      cp_config.skip_repo_update = ENV['COCOAPODS_NO_UPDATE']
      if ENV['COCOAPODS_VERBOSE']
        cp_config.verbose = true
      else
        cp_config.silent = true
      end

      cp_config.integrate_targets = false
      cp_config.installation_root = Pathname.new(File.expand_path(config.project_dir)) + 'vendor'
    end

    # DSL
    #-------------------------------------------------------------------------#

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

    # Installation & Linking
    #-------------------------------------------------------------------------#

    def pods_installer
      @installer ||= Pod::Installer.new(cp_config.sandbox, @podfile, cp_config.lockfile)
    end

    # Performs a CocoaPods Installation.
    #
    # For now we only support one Pods target, this will have to be expanded
    # once we work on more spec support.
    #
    # Let RubyMotion re-generate the BridgeSupport file whenever the list of
    # installed pods changes.
    #
    def install!
      pods_installer.install!
      if bridgesupport_file.exist? && !pods_installer.installed_specs.empty?
        bridgesupport_file.delete
      end
    end

    # Adds the Pods project to the RubyMotion config as a vendored project.
    #
    def link_project
      install_resources
      copy_headers

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
            path = search_path.first.gsub!(/(\$\(PODS_ROOT\))|(\$\{PODS_ROOT\})/, "#{@config.project_dir}/#{PODS_ROOT}")
            @config.framework_search_paths << path if path
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
        @config.weak_frameworks.concat(ldflags.scan(/-weak_framework\s+([^\s]+)/).map { |m| m[0] })
        @config.weak_frameworks.uniq!
        @config.libs.uniq!
      end
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
      @config.resources_dirs << resources_dir.to_s
    end

    def copy_headers
      headers = Dir.glob(["#{PODS_ROOT}/*.h", "#{PODS_ROOT}/*.pch"])
      headers.each do |header|
        header = File.basename(header)
        unless File.exist?("#{PODS_ROOT}/Headers/____#{header}")
          FileUtils.cp("#{PODS_ROOT}/#{header}", "#{PODS_ROOT}/Headers/____#{header}")
        end
      end
    end

    # Helpers
    #-------------------------------------------------------------------------#

    def cp_config
      Pod::Config.instance
    end

    def bridgesupport_file
      Pathname.new(@config.project_dir) + PODS_ROOT + 'Pods.bridgesupport'
    end

    def pods_xcconfig
      path = Pathname.new(@config.project_dir) + PODS_ROOT + 'Pods.xcconfig'
      Xcodeproj::Config.new(path)
    end

    def resources
      resources = []
      File.open(Pathname.new(@config.project_dir) + PODS_ROOT + 'Pods-resources.sh') { |f|
        f.each_line do |line|
          if matched = line.match(/install_resource\s+'(.*)'/)
            resources << Pathname.new(@config.project_dir) + PODS_ROOT + matched[1]
          end
        end
      }
      resources
    end

    def resources_dir
      Pathname.new(@config.project_dir) + PODS_ROOT + 'Resources'
    end

    def inspect
      ''
    end
  end
end
