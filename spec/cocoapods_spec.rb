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
  def installer_rep_from_post_install_hook=(installer); @installer_rep_from_post_install_hook = installer; end

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

        pod 'Reachability', '2.0.5'
        pod 'ASIHTTPRequest/ASIWebPageRequest', '1.8.1'

        post_install do |installer|
          context.installer_rep_from_post_install_hook = installer
        end

        context.installer = pods_installer
      end
    end
  end

  it "installs the Pods to vendor/Pods" do
    (Pathname.new(@config.project_dir) + 'vendor/Pods/ASIHTTPRequest').should.exist
  end

  it "configures CocoaPods to resolve dependency files for the iOS platform" do
    @podfile.target_definition_list.first.platform.should == :ios
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
    @installer_rep_from_post_install_hook.pods.map(&:name).should == ["ASIHTTPRequest", "Reachability"]
  end

  it "pods deployment target should equal to project deployment target" do
    @podfile.target_definition_list.first.platform.deployment_target.to_s.should == '5.0'
  end

  it "removes Pods.bridgesupport whenever the PODS section of Podfile.lock changes" do
    bs_file = @config.pods.bridgesupport_file
    bs_file.open('w') { |f| f.write 'ORIGINAL CONTENT' }
    lock_file = @installer.config.lockfile

    # Even if another section changes, it doesn't remove Pods.bridgesupport
    lockfile_data = lock_file.to_hash
    lockfile_data['DEPENDENCIES'] = []
    Pod::Lockfile.new(lockfile_data).write_to_disk(@installer.config.sandbox.manifest.defined_in_file)
    @config.pods.install!
    bs_file.read.should == 'ORIGINAL CONTENT'

    # If the PODS section changes, then Pods.bridgesupport is removed
    lockfile_data = lock_file.to_hash
    lockfile_data['PODS'] = []
    Pod::Lockfile.new(lockfile_data).write_to_disk(@installer.config.sandbox.manifest.defined_in_file)
    @installer.config.instance_variable_set(:@lockfile, nil)
    @config.pods.install!
    bs_file.should.not.exist
  end

  it 'should produce reasonably short config output' do
    @config.pods.inspect.should == ''
  end

end
