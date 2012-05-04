require File.expand_path('../spec_helper', __FILE__)

module Motion; module Project;
  class Vendor
    attr_reader :opts
  end
end; end

describe "CocoaPodsConfig" do
  extend SpecHelper::TemporaryDirectory

  before do
    Pod::Config.instance.repos_dir = ROOT + 'spec/fixtures/spec-repos'
  end

  it "configures CocoaPods to resolve dependency files for the iOS platform" do
    config = Motion::Project::Config.new(temporary_directory.to_s, :development)
    config.instance_eval do
      pods do
        dependency 'Reachability', '2.0.4' # the one that comes with ASIHTTPRequest
        dependency 'ASIHTTPRequest', '1.8.1'
      end
    end
    vendor = config.vendor_projects.find { |v| File.basename(v.path) == 'ASIHTTPRequest' }
    # This is an iOS *only* source file!
    vendor.opts[:source_files].grep(/ASIAuthenticationDialog/).should.not.be.empty
  end
end
