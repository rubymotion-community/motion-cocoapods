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

namespace :pod do
  task :update_spec_repos do
    if ENV['COCOCAPODS_NO_UPDATE']
      $stderr.puts(
        '[!] The COCOCAPODS_NO_UPDATE env variable has been deprecated, use ' \
        'COCOAPODS_NO_REPO_UPDATE instead.'
      )
      ENV['COCOAPODS_NO_REPO_UPDATE'] = '1'
    end

    show_output = !ENV['COCOAPODS_NO_REPO_UPDATE_OUTPUT']

    unless ENV['COCOAPODS_NO_REPO_UPDATE']
      Pod::SourcesManager.update(nil, show_output)
    end
  end

  desc "Download and integrate newly added pods"
  task :install => :update_spec_repos do
    # TODO Should ideally not have to be controller manually.
    Pod::UserInterface.title_level = 1

    pods = App.config.pods

    # TODO fix this, see https://git.io/vae3Z
    need_install = (pods.analyzer.needs_install? rescue true)

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
    dir = Motion::CocoaPods::PODS_ROOT
    if File.exist?(dir)
      App.info 'Delete', dir
      rm_rf dir
    end
  end
end
