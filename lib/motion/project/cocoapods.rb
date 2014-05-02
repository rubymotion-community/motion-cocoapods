# Copyright (c) 2012-2013, Laurent Sansonetti <lrz@hipbyte.com>
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
      end
      @pods
    end
  end

  class App
    class << self
      def build_with_cocoapods(platform, opts = {})
        unless File.exist?(CocoaPods::PODS_ROOT)
          $stderr.puts "[!] No CocoaPods dependencies found in #{CocoaPods::PODS_ROOT}, run the `rake pod:install` task."
          exit 1
        end
        build_without_cocoapods(platform, opts)
      end

      alias_method "build_without_cocoapods", "build"
      alias_method "build", "build_with_cocoapods"
    end
  end

  #---------------------------------------------------------------------------#

  class CocoaPods
    PODS_ROOT = 'vendor/Pods'

    attr_accessor :podfile

    def initialize(config)
      @config = config

      @podfile = Pod::Podfile.new(Pathname.new(Rake.original_dir) + 'Rakefile') {}
      @podfile.platform((App.respond_to?(:template) ? App.template : :ios), config.deployment_target)
      cp_config.podfile = @podfile
      cp_config.skip_repo_update = true
      cp_config.verbose = !!ENV['COCOAPODS_VERBOSE']
      cp_config.integrate_targets = false
      cp_config.installation_root = Pathname.new(File.expand_path(config.project_dir)) + 'vendor'

      configure_project
    end

    # Adds the Pods project to the RubyMotion config as a vendored project and
    #
    def configure_project
      @config.vendor_project(PODS_ROOT, :xcode,
        :target => 'Pods',
        :headers_dir => 'Headers',
        :products => %w{ libPods.a }
      )

      @config.resources_dirs << resources_dir.to_s

      # TODO replace this all once Xcodeproj has the proper xcconfig parser.
      if (xcconfig = self.pods_xcconfig_hash) && ldflags = xcconfig['OTHER_LDFLAGS']
        lib_search_paths = xcconfig['LIBRARY_SEARCH_PATHS'] || ""
        lib_search_paths.gsub!('$(PODS_ROOT)', "-L#{@config.project_dir}/#{PODS_ROOT}")

        @config.libs.concat(ldflags.scan(/-l([^\s]+)/).map { |m|
          if lib_search_paths.length == 0 || File.exist?("/usr/lib/lib#{m[0]}.dylib")
            "/usr/lib/lib#{m[0]}.dylib"
          else
            "#{lib_search_paths} -ObjC -l#{m[0]}"
          end
        })
        @config.libs.uniq!

        framework_search_paths = []
        if xcconfig['FRAMEWORK_SEARCH_PATHS']
          xcconfig['FRAMEWORK_SEARCH_PATHS'].scan(/\"([^\"]+)\"/) do |search_path|
            path = search_path.first.gsub!(/(\$\(PODS_ROOT\))|(\$\{PODS_ROOT\})/, "#{@config.project_dir}/#{PODS_ROOT}")
            framework_search_paths << path if path
          end
        end
        @config.framework_search_paths.concat(framework_search_paths)

        frameworks = ldflags.scan(/-framework\s+([^\s]+)/).map { |m| m[0] }
        @config.frameworks.concat(frameworks)
        @config.frameworks.uniq!

        if @config.deploy_platform == 'MacOSX'
          framework_search_paths.each do |framework_search_path|
            frameworks.each do |framework|
              path = File.join(framework_search_path, "#{framework}.framework")
              if File.exist?(path)
                @config.embedded_frameworks << path
              end
            end
          end
        end

        @config.weak_frameworks.concat(ldflags.scan(/-weak_framework\s+([^\s]+)/).map { |m| m[0] })
        @config.weak_frameworks.uniq!
      end
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

    # Installation
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
    def install!(update)
      pods_installer.update = update
      pods_installer.install!
      if bridgesupport_file.exist? && !pods_installer.installed_specs.empty?
        bridgesupport_file.delete
      end

      install_resources
      copy_cocoapods_env_and_prefix_headers
    end

    # TODO this probably breaks in cases like resource bundles etc, need to test.
    #
    def install_resources
      FileUtils.mkdir_p(resources_dir)
      resources.each do |file|
        begin
          FileUtils.cp_r(file, resources_dir) if file.exist?
        rescue ArgumentError => exc
          unless exc.message =~ /same file/
            raise
          end
        end
      end
    end

    HEADERS_ROOT = File.join(PODS_ROOT, 'Headers')

    def copy_cocoapods_env_and_prefix_headers
      headers = Dir.glob(["#{PODS_ROOT}/*.h", "#{PODS_ROOT}/*.pch"])
      headers.each do |header|
        src = File.basename(header)
        dst = src.sub(/\.pch$/, '.h')
        dst_path = File.join(HEADERS_ROOT, "____#{dst}")
        unless File.exist?(dst_path)
          FileUtils.mkdir_p(HEADERS_ROOT)
          FileUtils.cp(File.join(PODS_ROOT, src), dst_path)
        end
      end
    end

    # Helpers
    #-------------------------------------------------------------------------#

    def cp_config
      Pod::Config.instance
    end

    def analyzer
      cp_config = Pod::Config.instance
      Pod::Installer::Analyzer.new(cp_config.sandbox, @podfile, cp_config.lockfile)
    end

    def bridgesupport_file
      Pathname.new(@config.project_dir) + PODS_ROOT + 'Pods.bridgesupport'
    end

    def pods_xcconfig
      path = Pathname.new(@config.project_dir) + PODS_ROOT + 'Pods.xcconfig'
      Xcodeproj::Config.new(path) if path.exist?
    end

    def pods_xcconfig_hash
      if xcconfig = pods_xcconfig
        xcconfig.to_hash
      end
    end

    # Do not copy `.framework` bundles, these should be handled through RM's
    # `embedded_frameworks` config attribute.
    #
    def resources
      resources = []
      File.open(Pathname.new(@config.project_dir) + PODS_ROOT + 'Pods-resources.sh') { |f|
        f.each_line do |line|
          if matched = line.match(/install_resource\s+(.*)/)
            path = (matched[1].strip)[1..-2]
            path.sub!("${BUILD_DIR}/${CONFIGURATION}${EFFECTIVE_PLATFORM_NAME}", ".build")
            unless File.extname(path) == '.framework'
              resources << Pathname.new(@config.project_dir) + PODS_ROOT + path
            end
          end
        end
      }
      resources
    end

    def resources_dir
      Pathname.new(@config.project_dir) + PODS_ROOT + 'Resources'
    end
  end
end

namespace :pod do
  task :update_spec_repos do
    if ENV['COCOCAPODS_NO_UPDATE']
      $stderr.puts '[!] The COCOCAPODS_NO_UPDATE env variable has been deprecated, use COCOAPODS_NO_REPO_UPDATE instead.'
      ENV['COCOAPODS_NO_REPO_UPDATE'] = '1'
    end
    show_output = !ENV['COCOAPODS_NO_REPO_UPDATE_OUTPUT']
    Pod::SourcesManager.update(nil, show_output) unless ENV['COCOAPODS_NO_REPO_UPDATE']
  end

  desc "Download and integrate newly added pods"
  task :install => :update_spec_repos do
    # TODO Should ideally not have to be controller manually.
    Pod::UserInterface.title_level = 1
    pods = App.config.pods
    begin
      need_install = pods.analyzer.needs_install?
    rescue
      # TODO fix this, see https://github.com/HipByte/motion-cocoapods/issues/57#issuecomment-17810809
      need_install = true
    end
    # TODO Should ideally not have to be controller manually.
    Pod::UserInterface.title_level = 0
    pods.install!(false) if need_install
  end

  desc "Update outdated pods"
  task :update => :update_spec_repos do
    pods = App.config.pods
    pods.install!(true)
  end
end

namespace :clean do
  # This gets appended to the already existing clean:all task.
  task :all do
    dir = Motion::Project::CocoaPods::PODS_ROOT
    if File.exist?(dir)
      App.info 'Delete', dir
      rm_rf dir
    end
  end
end
