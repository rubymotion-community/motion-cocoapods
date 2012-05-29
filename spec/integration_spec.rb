require File.expand_path('../spec_helper', __FILE__)

describe "CocoaPods integration" do
  extend SpecHelper::TemporaryDirectory

  before do
    @project_dir = ROOT + 'spec/fixtures/RestKitTest'
    FileUtils.rm_rf @project_dir + 'build'
    FileUtils.rm_rf @project_dir + 'vendor'
  end

  it "successfully builds an application" do
    ENV.delete('COCOAPODS_NO_UPDATE')
    system("cd '#{@project_dir}' && rake build:simulator").should == true
  end
end
