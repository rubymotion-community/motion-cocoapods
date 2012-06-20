require File.expand_path('../spec_helper', __FILE__)

module Motion; module Project;
  class Vendor
    attr_reader :opts
  end
end; end

describe "CocoaPodsConfig" do
  extend SpecHelper::TemporaryDirectory

  def podfile=(podfile); @podfile = podfile; end
  def installer=(installer); @installer = installer; end
  def installer_from_post_install_hook=(installer); @installer_from_post_install_hook = installer; end

  before do
    #ENV['COCOAPODS_VERBOSE'] = '1'
    ENV['COCOAPODS_NO_UPDATE'] = '1'

    Pod::Config.instance.repos_dir = ROOT + 'spec/fixtures/spec-repos'

    context = self

    @config = Motion::Project::Config.new(temporary_directory.to_s, :development)
    @config.deployment_target = '5.0'
    @config.instance_eval do
      pods do
        context.podfile = @podfile

        dependency 'Reachability', '2.0.5'
        dependency 'ASIWebPageRequest', '1.8.1'

        post_install do |installer|
          context.installer_from_post_install_hook = installer
        end

        context.installer = pods_installer
      end
    end
  end

  it "installs the Pods to vendor/Pods" do
    (Pathname.new(@config.project_dir) + 'vendor/Pods/ASIHTTPRequest').should.exist
  end

  it "configures CocoaPods to resolve dependency files for the iOS platform" do
    if Motion::Project::CocoaPods.cocoapods_v06_and_higher?
      @podfile.target_definitions[:default].platform.should == :ios
    else
      Pod::Config.instance.rootspec.platform.should == :ios
      @podfile.platform.should == :ios
    end
  end

  it "writes Podfile.lock to vendor/" do
    (Pathname.new(@config.project_dir) + 'vendor/Podfile.lock').should.exist
  end

  it "adds Pods.xcodeproj as a vendor project" do
    project = @config.vendor_projects.last
    project.path.should == 'vendor/Pods'
    project.opts[:headers_dir].should == 'Headers'
    project.opts[:products].should == %w{ libPods.a }
  end

  it "adds all the required frameworks and libraries" do
    @config.frameworks.sort.should == %w{ CFNetwork CoreGraphics Foundation MobileCoreServices SystemConfiguration UIKit }
    @config.libs.sort.should == %w{ /usr/lib/libxml2.2.7.3.dylib /usr/lib/libz.1.dylib }
  end

  it "runs the post_install hook" do
    @installer_from_post_install_hook.should == @installer
  end

  it "pods deployment target should equal to project deployment target" do
    if Motion::Project::CocoaPods.cocoapods_v06_and_higher?
      @installer.config.podfile.target_definitions[:default].platform.deployment_target.to_s.should == '5.0'
    else
      Pod::Config.instance.rootspec.platform.options[:deployment_target].should == '5.0'
    end
  end
  
end
