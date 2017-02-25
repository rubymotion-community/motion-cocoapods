require File.expand_path('../spec_helper', __FILE__)

describe "motion-cocoapods" do
  extend SpecHelper::TemporaryDirectory

  def podfile=(podfile); @podfile = podfile; end
  def installer=(installer); @installer = installer; end

  before do
    unless @ran_install
      teardown_temporary_directory
      setup_temporary_directory

      Pod::Config.instance.silent = true
      #ENV['COCOAPODS_VERBOSE'] = '1'

      context = self

      @config = App.config
      @config.project_dir = temporary_directory.to_s
      @config.deployment_target = '6.0'
      @config.instance_eval do
        pods do
          context.podfile = @podfile

          pod 'AFNetworking', '1.3.2'
          pod 'TransformerKit', '0.5.3'
          pod 'AFIncrementalStore', '0.5.1' # depends on AFNetworking ~> 1.3.2, but 1.3.3 exists.
          pod 'AFKissXMLRequestOperation'
          pod 'KissXML', '5.0.1'
          pod 'HockeySDK', '> 3.6.0', '< 3.6.2' # so 3.6.1, just testing that multiple requirements works
          pod 'GoogleAnalytics', '3.13.0'
          pod 'GoogleMobileAds', '7.7.1'

          context.installer = pods_installer
        end
      end

      @installed_pods_name = nil
      Pod::HooksManager.register('motion_cocoapods_spec', :post_install) { |installer|
        @installed_pods_name = installer.pod_targets.map(&:name) if installer
      }
    end
  end

  it "pods deployment target should equal to project deployment target" do
    @podfile.target_definition_list.first.platform.deployment_target.to_s.should == '6.0'
  end

  it "sets the Rakefile as the location of the Podfile" do
    @podfile.defined_in_file.should == Pathname.new(Rake.original_dir) + 'Rakefile'
  end

  before do
    unless @ran_install
      Rake::Task['pod:install'].invoke
      @config.pods.configure_project
      @ran_install = true
    end
  end

  it "adds all the system frameworks and libraries" do
    rm_default = %w{ UIKit Foundation CoreGraphics CoreFoundation CFNetwork CoreAudio }
    afnetworking = %w{ CoreGraphics MobileCoreServices Security SystemConfiguration }
    afincrementalstore = %w{ CoreData }
    hockey = %w{ AssetsLibrary CoreText CoreGraphics MobileCoreServices QuartzCore QuickLook Security SystemConfiguration UIKit }
    googleAds = %w{ AudioToolbox AVFoundation CoreGraphics CoreMedia CoreTelephony EventKit EventKitUI MediaPlayer MessageUI StoreKit SystemConfiguration }
    @config.frameworks.sort.should == (rm_default + afnetworking + afincrementalstore + hockey + googleAds).uniq.sort
    @config.libs.should.include '/usr/lib/libxml2.dylib'
  end

  it "adds a prebuilt (static library) framework to the linked libs" do
    @config.libs.should.include "-ObjC '#{File.join(@config.project_dir, 'vendor/Pods/HockeySDK/Vendor/CrashReporter.framework/CrashReporter')}'"
  end

  # TODO add test for OS X with embedded frameworks or iOS >= 8 that has dynamic libraries
  #
  #it "adds a prebuilt framework to the embedded_frameworks" do
    #@config.embedded_frameworks.should == [File.join(@config.project_dir, 'vendor/Pods/HockeySDK/Vendor/CrashReporter.framework')]
  #end

  it "installs the Pods to vendor/Pods" do
    (Pathname.new(@config.project_dir) + 'vendor/Pods/AFNetworking').should.exist
    (Pathname.new(@config.project_dir) + 'vendor/Pods/AFIncrementalStore').should.exist
    (Pathname.new(@config.project_dir) + 'vendor/Pods/AFKissXMLRequestOperation').should.exist
  end

  it "configures CocoaPods to resolve dependency files for the iOS platform" do
    @podfile.target_definition_list.first.platform.should == :ios
  end

  it "writes Podfile.lock to vendor/" do
    (Pathname.new(@config.project_dir) + 'vendor/Podfile.lock').should.exist
  end

  it "adds Pods.xcodeproj as a vendor project with header dirs including all vendored_frameworks" do
    project = @config.vendor_projects.last
    project.path.should == 'vendor/Pods'
    project.opts[:headers_dir].should == 'Headers/Public'
    project.opts[:products].should == %w{
      libAFIncrementalStore.a
      libAFKissXMLRequestOperation.a
      libAFNetworking.a
      libHockeySDK.a
      libInflectorKit.a
      libKissXML.a
      libTransformerKit.a
    }
    project.opts[:bridgesupport_cflags].should.include('Headers/Public/GoogleMobileAds')
  end

  it "runs the post_install hook" do
    Pod::HooksManager.run(:post_install, @installer)
    @installed_pods_name.should == [
      "AFIncrementalStore",
      "AFKissXMLRequestOperation",
      "AFNetworking",
      "GoogleAnalytics",
      "GoogleMobileAds",
      "HockeySDK",
      "InflectorKit",
      "KissXML",
      "TransformerKit",
    ]
  end

  it "provides a list of the activated pods on #inspect, which is used in `rake config`" do
    @config.pods.inspect.should == [
      'AFIncrementalStore (0.5.1)',
      'AFKissXMLRequestOperation (0.0.1)',
      'AFNetworking (1.3.2)',
      'GoogleAnalytics (3.13.0)',
      'GoogleMobileAds (7.7.1)',
      'HockeySDK (3.6.1)',
      'InflectorKit (0.0.1)',
      'KissXML (5.0.1)',
      'TransformerKit (0.5.3)',
      'TransformerKit/Core (0.5.3)',
      'TransformerKit/Cryptography (0.5.3)',
      'TransformerKit/Data (0.5.3)',
      'TransformerKit/Date (0.5.3)',
      'TransformerKit/Image (0.5.3)',
      'TransformerKit/JSON (0.5.3)',
      'TransformerKit/String (0.5.3)',
    ].inspect
  end
end
