require File.expand_path('../spec_helper', __FILE__)

describe "use_frameworks!" do
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
      @config.deployment_target = '9.0'
      @config.instance_eval do
        pods do
          context.podfile = @podfile

          use_frameworks!
          pod 'Google-Mobile-Ads-SDK', '= 7.18.0' # pre-built static framework
          pod 'google-cast-sdk', '= 3.3.0' # pre-built dynamic framework
          pod 'SDWebImage', '= 3.7.6'
          context.installer = pods_installer
        end
      end

      @installed_pods_name = nil
      Pod::HooksManager.register('motion_cocoapods_spec', :post_install) { |installer|
        @installed_pods_name = installer.pod_targets.map(&:name) if installer
      }
    end
  end

  before do
    unless @ran_install
      Rake::Task['pod:install'].invoke
      @config.pods.configure_project
      @ran_install = true
    end
  end

  it "adds a prebuilt dynamic framework to the embedded_frameworks" do
    framework = File.join(@config.project_dir, 'vendor/Pods/google-cast-sdk/GoogleCastSDK-Public-3.3.0-Release/GoogleCast.framework')
    @config.embedded_frameworks.should == [framework]
  end

  it "adds a prebuilt static framework to the config.libs" do
    lib = "-ObjC '#{File.join(@config.project_dir, "/vendor/Pods/Google-Mobile-Ads-SDK/Frameworks/frameworks/GoogleMobileAds.framework/GoogleMobileAds")}'"
    @config.libs.include?(lib).should == true
  end

  # To generate bridgesupport, it require RubyMotion 4.18+
  # it "should generate bridgesupport file of prebuilt static framework" do
  #   path = File.expand_path(File.join(
  #     '~/Library/RubyMotion/build',
  #     File.expand_path(@config.project_dir),
  #     "vendor/Pods/Google-Mobile-Ads-SDK/Frameworks/frameworks/GoogleMobileAds.framework.bridgesupport"
  #   ))
  #   Pathname.new(path).should.exist
  # end

  it "installs the Pods to vendor/Pods" do
    (Pathname.new(@config.project_dir) + 'vendor/Pods/google-cast-sdk').should.exist
    (Pathname.new(@config.project_dir) + 'vendor/Pods/Google-Mobile-Ads-SDK').should.exist
    (Pathname.new(@config.project_dir) + 'vendor/Pods/SDWebImage').should.exist
  end

  it "provides a list of the activated pods on #inspect, which is used in `rake config`" do
    @config.pods.inspect.should == [
      "google-cast-sdk (3.3.0)",
      "google-cast-sdk/Core (3.3.0)",
      "Google-Mobile-Ads-SDK (7.18.0)",
      "SDWebImage (3.7.6)",
      "SDWebImage/Core (3.7.6)"
    ].inspect
  end
end