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

module Motion
  module Project
    class Config
      variable :pods

      def pods(vendor_options = {}, &block)
        @pods ||= Motion::CocoaPods.new(self, vendor_options)
        @pods.instance_eval(&block) if block
        @pods
      end
    end

    class App
      class << self
        def build_with_cocoapods(platform, opts = {})
          unless File.exist?(CocoaPods::PODS_ROOT)
            $stderr.puts(
              "[!] No CocoaPods dependencies found in " \
              "#{CocoaPods::PODS_ROOT}, run the " \
              "`[bundle exec] rake pod:install` task."
            )
            exit 1
          end
          build_without_cocoapods(platform, opts)
        end

        alias_method "build_without_cocoapods", "build"
        alias_method "build", "build_with_cocoapods"
      end
    end
  end
end
