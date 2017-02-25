# coding: utf-8
# Copyright (c) 2012-2014, Laurent Sansonetti <lrz@hipbyte.com>
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

module Motion::Project
  class Config
    variable :pods

    def pods(vendor_options = {}, &block)
      @pods ||= Motion::Project::CocoaPods.new(self, vendor_options)
      if block
        @pods.instance_eval(&block)
      end
      @pods.configure_project
      @pods
    end
  end

  class App
    class << self
      def build_with_cocoapods(platform, opts = {})
        unless File.exist?(CocoaPods::PODS_ROOT)
          $stderr.puts "[!] No CocoaPods dependencies found in #{CocoaPods::PODS_ROOT}, run the `[bundle exec] rake pod:install` task."
          exit 1
        end
        build_without_cocoapods(platform, opts)

        # Install the resource which will be generated after built
        installed_resources = App.config.pods.install_resources
        unless installed_resources.empty?
          app_resources_dir = config.app_resources_dir(platform)
          installed_resources.each do |path|
            App.builder.copy_resource(path.to_s, File.join(app_resources_dir, path.basename.to_s))
          end
        end
      end

      alias_method "build_without_cocoapods", "build"
      alias_method "build", "build_with_cocoapods"
    end
  end

  #---------------------------------------------------------------------------#

  class CocoaPods
    PODS_ROOT = 'vendor/Pods'
    TARGET_NAME = 'RubyMotion'
    SUPPORT_FILES = File.join(PODS_ROOT, "Target Support Files/Pods-#{TARGET_NAME}")

    attr_accessor :podfile

    def initialize(config, vendor_options)
      @config = config
      @vendor_options = vendor_options
      @use_frameworks = false

      case @config.deploy_platform
      when 'MacOSX'
        platform = :osx
      when 'iPhoneOS'
        platform = :ios
      when 'AppleTVOS'
        platform = :tvos
      when 'WatchOS'
        platform = :watchos
      else
        App.fail "Unknown CocoaPods platform: #{@config.deploy_platform}"
      end

      @podfile = Pod::Podfile.new(Pathname.new(Rake.original_dir) + 'Rakefile') {}
      @podfile.platform(platform, config.deployment_target)
      @podfile.target(TARGET_NAME)
      cp_config.podfile = @podfile
      cp_config.installation_root = Pathname.new(File.expand_path(config.project_dir)) + 'vendor'

      if cp_config.verbose = !!ENV['COCOAPODS_VERBOSE']
        require 'claide'
      end
    end

    # Adds the Pods project to the RubyMotion config as a vendored project and
    #
    def configure_project
      if self.pods_xcconfig_hash
        @config.resources_dirs << resources_dir.to_s

        frameworks = installed_frameworks[:pre_built]
        if frameworks
          @config.embedded_frameworks += frameworks
          @config.embedded_frameworks.uniq!
        end

        if @use_frameworks
          configure_project_frameworks
        else
          configure_project_static_libraries
        end
      end
    end

    def configure_project_frameworks
      if (xcconfig = self.pods_xcconfig_hash) && ldflags = xcconfig['OTHER_LDFLAGS']
        # Add libraries to @config.libs
        pods_libraries

        frameworks = ldflags.scan(/-framework\s+"?([^\s"]+)"?/).map { |m| m[0] }
        if build_frameworks = installed_frameworks[:build]
          build_frameworks = build_frameworks.map { |path| File.basename(path, ".framework") }
          frameworks.delete_if { |f| build_frameworks.include?(f) }
        end
        static_frameworks = pods_frameworks(frameworks)
        static_frameworks_paths = static_frameworks_paths(static_frameworks)
        search_path = static_frameworks_paths.inject("") { |s, path|
          s += " -I'#{path}' -I'#{path}/Headers'"
        }
        @vendor_options[:bridgesupport_cflags] ||= ''
        @vendor_options[:bridgesupport_cflags] << " #{header_search_paths} #{search_path}"

        @config.weak_frameworks.concat(ldflags.scan(/-weak_framework\s+([^\s]+)/).map { |m| m[0] })
        @config.weak_frameworks.uniq!

        vendors = @config.vendor_project(PODS_ROOT, :xcode, {
          :target => "Pods-#{TARGET_NAME}",
        }.merge(@vendor_options))

        vendor = vendors.last
        if vendor.respond_to?(:generate_bridgesupport)
          static_frameworks_paths.each do |path|
            path = File.expand_path(path)
            bs_file = File.join(Builder.common_build_dir, "#{path}.bridgesupport")
            headers = Dir.glob(File.join(path, '**{,/*/**}/*.h'))
            vendor.generate_bridgesupport(@config.deploy_platform, bs_file, headers)
          end
        end
      end
    end

    def configure_project_static_libraries
      # TODO replace this all once Xcodeproj has the proper xcconfig parser.
      if (xcconfig = self.pods_xcconfig_hash) && ldflags = xcconfig['OTHER_LDFLAGS']
        # Collect the Pod products
        pods_libs = pods_libraries

        # Initialize ':bridgesupport_cflags', in case the use
        @vendor_options[:bridgesupport_cflags] ||= ''
        @vendor_options[:bridgesupport_cflags] << " #{header_search_paths}"

        frameworks = ldflags.scan(/-framework\s+"?([^\s"]+)"?/).map { |m| m[0] }
        pods_frameworks(frameworks)

        @config.weak_frameworks.concat(ldflags.scan(/-weak_framework\s+([^\s]+)/).map { |m| m[0] })
        @config.weak_frameworks.uniq!

        @config.vendor_project(PODS_ROOT, :xcode, {
          :target => "Pods-#{TARGET_NAME}",
          :headers_dir => "Headers/Public",
          :products => pods_libs.map { |lib_name| "lib#{lib_name}.a" },
          :allow_empty_products => pods_libs.empty?,
        }.merge(@vendor_options))
      end
    end

    # DSL
    #-------------------------------------------------------------------------#

    def source(source)
      @podfile.source(source)
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

    def use_frameworks!(flag = true)
      @use_frameworks = flag
      @podfile.use_frameworks!(flag)
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
      FileUtils.rm_rf(resources_dir)

      pods_installer.update = update
      pods_installer.installation_options.integrate_targets = false
      pods_installer.install!
      install_resources
      copy_cocoapods_env_and_prefix_headers
    end

    # TODO this probably breaks in cases like resource bundles etc, need to test.
    #
    def install_resources
      FileUtils.mkdir_p(resources_dir)

      installed_resources = []
      resources.each do |file|
        begin
          dst = resources_dir + file.basename
          if file.exist? && !dst.exist?
            FileUtils.cp_r(file, resources_dir)
            installed_resources << dst
          end
        rescue ArgumentError => exc
          unless exc.message =~ /same file/
            raise
          end
        end
      end

      installed_resources 
    end

    PUBLIC_HEADERS_ROOT = File.join(PODS_ROOT, 'Headers/Public')

    def copy_cocoapods_env_and_prefix_headers
      headers = Dir.glob(["#{PODS_ROOT}/*.h", "#{PODS_ROOT}/*.pch", "#{PODS_ROOT}/Target Support Files/**/*.h", "#{PODS_ROOT}/Target Support Files/**/*.pch"])
      headers.each do |header|
        src = File.basename(header)
        dst = src.sub(/\.pch$/, '.h')
        dst_path = File.join(PUBLIC_HEADERS_ROOT, "____#{dst}")
        unless File.exist?(dst_path)
          FileUtils.mkdir_p(PUBLIC_HEADERS_ROOT)
          FileUtils.cp(header, dst_path)
        end
      end
    end

    # Helpers
    #-------------------------------------------------------------------------#

    # This is the output that gets shown in `rake config`, so it should be
    # short and sweet.
    #
    def inspect
      cp_config.lockfile.to_hash['PODS'].map do |pod|
        pod.is_a?(Hash) ? pod.keys.first : pod
      end.inspect
    end

    def cp_config
      Pod::Config.instance
    end

    def analyzer
      cp_config = Pod::Config.instance
      Pod::Installer::Analyzer.new(cp_config.sandbox, @podfile, cp_config.lockfile)
    end

    def pods_xcconfig
      @pods_xcconfig ||= begin
        path = Pathname.new(@config.project_dir) + SUPPORT_FILES + "Pods-#{TARGET_NAME}.release.xcconfig"
        Xcodeproj::Config.new(path) if path.exist?
      end
      @pods_xcconfig
    end

    def pods_xcconfig_hash
      if xcconfig = pods_xcconfig
        xcconfig.to_hash
      end
    end

    def pods_libraries
      xcconfig = pods_xcconfig_hash
      ldflags = xcconfig['OTHER_LDFLAGS']

      # Get the name of all static libraries that come pre-built with pods
      pre_built_static_libs = lib_search_paths.map do |path|
        Dir[File.join(path, '**/*.a')].map { |f| File.basename(f) }
      end.flatten

      pods_libs = []
      @config.libs.concat(ldflags.scan(/-l"?([^\s"]+)"?/).map { |m|
        lib_name = m[0]
        next if lib_name.nil?
        if lib_name.start_with?('Pods-')
          # For CocoaPods 0.37.x or below. This block is marked as deprecated.
          pods_libs << lib_name
          nil
        elsif pre_built_static_libs.include?("lib#{lib_name}.a")
          "#{lib_search_path_flags} -ObjC -l#{lib_name}"
        elsif File.exist?("/usr/lib/lib#{lib_name}.dylib")
          "/usr/lib/lib#{lib_name}.dylib"
        else
          pods_libs << lib_name
          nil
        end
      }.compact)
      @config.libs.uniq!

      pods_libs
    end

    def pods_frameworks(frameworks)
      frameworks = frameworks.dup
      if installed_frameworks[:pre_built]
        installed_frameworks[:pre_built].each do |pre_built|
          frameworks.delete(File.basename(pre_built, ".framework"))
        end
      end

      static_frameworks = []
      case @config.deploy_platform
      when 'MacOSX'
        @config.framework_search_paths.concat(framework_search_paths)
        @config.framework_search_paths.uniq!
        framework_search_paths.each do |framework_search_path|
          frameworks.reject! do |framework|
            path = File.join(framework_search_path, "#{framework}.framework")
            if File.exist?(path)
              @config.embedded_frameworks << path
              true
            else
              false
            end
          end
        end
      when 'iPhoneOS', 'AppleTVOS', 'WatchOS'
        pods_root = cp_config.installation_root + 'Pods'
        # If we would really specify these as ‘frameworks’ then the linker
        # would not link the archive into the application, because it does not
        # see any references to any of the symbols in the archive. Treating it
        # as a static library (which it is) with `-ObjC` fixes this.
        #
        framework_search_paths.each do |framework_search_path|
          frameworks.reject! do |framework|
            path = File.join(framework_search_path, "#{framework}.framework")
            if File.exist?(path)
              @config.libs << "-ObjC '#{File.join(path, framework)}'"
              static_frameworks << framework
              true
            else
              false
            end
          end
        end
      end

      @config.frameworks.concat(frameworks)
      @config.frameworks.uniq!

      static_frameworks
    end        

    def lib_search_path_flags
      lib_search_paths
      @lib_search_path_flags
    end

    def lib_search_paths
      @lib_search_paths ||= begin
        xcconfig = pods_xcconfig_hash
        @lib_search_path_flags = xcconfig['LIBRARY_SEARCH_PATHS'] || ""

        paths = []
        @lib_search_path_flags = @lib_search_path_flags.split(/\s/).map do |path|
          if path =~ /(\$\(inherited\))|(\$\{inherited\})|(\$CONFIGURATION_BUILD_DIR)|(\$PODS_CONFIGURATION_BUILD_DIR)/
            nil
          else
            path = path.gsub(/(\$\(PODS_ROOT\))|(\$\{PODS_ROOT\})/, File.join(@config.project_dir, PODS_ROOT))
            paths << path.gsub('"', '')
            '-L ' << path
          end
        end.compact.join(' ')
        paths
      end

      @lib_search_paths
    end

    def framework_search_paths
      @framework_search_paths ||= begin
        xcconfig = pods_xcconfig_hash

        paths = []
        if search_paths = xcconfig['FRAMEWORK_SEARCH_PATHS']
          search_paths = search_paths.strip
          unless search_paths.empty?
            search_paths.scan(/"([^"]+)"/) do |search_path|
              path = search_path.first.gsub!(/(\$\(PODS_ROOT\))|(\$\{PODS_ROOT\})/, "#{@config.project_dir}/#{PODS_ROOT}")
              paths << path if path
            end
            # If we couldn't parse any search paths, then presumably nothing was properly quoted, so
            # fallback to just assuming the whole value is one path.
            if paths.empty?
              path = search_paths.gsub!(/(\$\(PODS_ROOT\))|(\$\{PODS_ROOT\})/, "#{@config.project_dir}/#{PODS_ROOT}")
              paths << path if path
            end
          end
        end
        paths
      end

      @framework_search_paths
    end

    def header_search_paths
      @header_search_paths ||= begin
        xcconfig = pods_xcconfig_hash

        paths = []
        if search_paths = xcconfig['HEADER_SEARCH_PATHS']
          search_paths = search_paths.strip
          unless search_paths.empty?
            search_paths.scan(/"([^"]+)"/) do |search_path|
              path = search_path.first.gsub!(/(\$\(PODS_ROOT\))|(\$\{PODS_ROOT\})/, "#{@config.project_dir}/#{PODS_ROOT}")
              paths << File.expand_path(path) if path
            end
            # If we couldn't parse any search paths, then presumably nothing was properly quoted, so
            # fallback to just assuming the whole value is one path.
            if paths.empty?
              path = search_paths.gsub!(/(\$\(PODS_ROOT\))|(\$\{PODS_ROOT\})/, "#{@config.project_dir}/#{PODS_ROOT}")
              paths << File.expand_path(path) if path
            end
          end
        end
        paths.map { |p| "-I'#{p}'" }.join(' ')
      end

      @header_search_paths
    end

    def static_frameworks_paths(frameworks)
      paths = []
      framework_search_paths.each do |framework_search_path|
        paths += Dir.glob("#{framework_search_path}/*.framework")
      end
      paths.keep_if { |path| 
        frameworks.include?(File.basename(path, ".framework"))
      }
      paths
    end

    # Do not copy `.framework` bundles, these should be handled through RM's
    # `embedded_frameworks` config attribute.
    #
    def resources
      resources = []
      File.open(Pathname.new(@config.project_dir) + SUPPORT_FILES + "Pods-#{TARGET_NAME}-resources.sh") { |f|
        f.each_line do |line|
          if matched = line.match(/install_resource\s+(.*)/)
            path = (matched[1].strip)[1..-2]
            if path.include?("$PODS_CONFIGURATION_BUILD_DIR")
              path = File.join(".build", File.basename(path))
            end
            unless File.extname(path) == '.framework'
              resources << Pathname.new(@config.project_dir) + PODS_ROOT + path
            end
          end
        end
      }
      resources.uniq
    end

    def resources_dir
      Pathname.new(@config.project_dir) + PODS_ROOT + 'Resources'
    end

    def installed_frameworks
      return @installed_frameworks if @installed_frameworks

      @installed_frameworks = {}
      path = Pathname.new(@config.project_dir) + SUPPORT_FILES + "Pods-#{TARGET_NAME}-frameworks.sh"
      return @installed_frameworks unless path.exist? 

      @installed_frameworks[:pre_built] = []
      @installed_frameworks[:build] = []

      File.open(path) { |f|
        f.each_line do |line|
          if matched = line.match(/install_framework\s+(.*)/)
            path = (matched[1].strip)[1..-2]
            if path.include?('${PODS_ROOT}')
              path = path.sub('${PODS_ROOT}', PODS_ROOT)
              @installed_frameworks[:pre_built] << File.join(@config.project_dir, path)
              @installed_frameworks[:pre_built].uniq!
            elsif path.include?('$BUILT_PRODUCTS_DIR')
              path = path.sub('$BUILT_PRODUCTS_DIR', "#{PODS_ROOT}/.build")
              @installed_frameworks[:build] << File.join(@config.project_dir, path)
              @installed_frameworks[:build].uniq!
            end
          end
        end
      }
      @installed_frameworks
    end

  end
end

namespace :pod do
  task :update_spec_repos do
    $stderr.puts '[!] If you need to update CocoaPods repository to install newer libraries, please run "pod repo update" command before.'
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
