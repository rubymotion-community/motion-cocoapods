require File.expand_path('../spec_helper', __FILE__)

module Motion; module Project;
  class Vendor
    attr_reader :opts
  end
end; end

describe "CocoaPodsConfig" do
  extend SpecHelper::TemporaryDirectory

  before do
    #ENV['COCOAPODS_VERBOSE'] = '1'

    Pod::Config.instance.repos_dir = ROOT + 'spec/fixtures/spec-repos'

    @config = Motion::Project::Config.new(temporary_directory.to_s, :development)
    @config.instance_eval do
      pods do
        dependency 'Reachability', '2.0.4' # the one that comes with ASIHTTPRequest
        dependency 'ASIHTTPRequest', '1.8.1'

        spec = pods_installer.target_installers.first.build_specifications.find { |spec| spec.name == 'ASIHTTPRequest' }
        # Adding an extra library purely for testing purposes.
        spec.libraries = 'z.1', 'xml2'
      end
    end
  end

  it "installs the Pods to vendor/Pods" do
    (Pathname.new(@config.project_dir) + 'vendor/Pods/ASIHTTPRequest').should.exist
  end

  it "configures CocoaPods to resolve dependency files for the iOS platform" do
    Pod::Config.instance.rootspec.platform.should == :ios
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
    @config.libs.sort.should == %w{ /usr/lib/libxml2.dylib /usr/lib/libz.1.dylib }
  end
end
