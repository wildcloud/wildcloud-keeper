# Copyright 2011 Marek Jelen
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'fileutils'

require 'wildcloud/keeper/configuration'
require 'wildcloud/keeper/logger'

module Wildcloud
  module Keeper
    module Deployers
      class Aufs

        def deploy(options = {})
          options[:base_image] ||= 'base'

          @id = options[:id]
          @appid = options[:appid]

          @temp_file    = File.join(config['paths']['tmp'],     "#{@id}.tar.gz")
          @image_path   = File.join(config['paths']['images'],  "#{@id}")
          @target_path  = File.join(config['paths']['mounts'],  "#{@id}")
          @temp_path    = File.join(config['paths']['temp'],    "#{@id}")

          FileUtils.mkdir_p(@image_path)
          FileUtils.mkdir_p(@target_path)
          FileUtils.mkdir_p(@temp_path)

          @branches = "br=#{@image_path}=rw:#{File.join(config['paths']['images'], 'base')}=ro"
          options[:root_path] = @image_path

          unless options[:build]
            run("curl -v -o #{@temp_file} -H 'X-Appid: #{config['storage']['id']}' #{config['storage']['url']}/#{@appid}.tar.gz")
            run("tar -xf #{@temp_file} -C #{@image_path}")
            @branches = "br=#{@temp_path}=rw:#{@image_path}=ro:#{File.join(config['paths']['images'], options[:base_image])}=ro"
            options[:root_path] = @temp_path
          end

          run("mount -t aufs -o #{@branches} none #{@target_path}")
        end

        def undeploy(options)

          @id ||= options[:id]
          @appid ||= options[:appid]

          @temp_file    ||= File.join(config['paths']['tmp'],     "#{@id}.tar.gz")
          @image_path   ||= File.join(config['paths']['images'],  "#{@id}")
          @target_path  ||= File.join(config['paths']['mounts'],  "#{@id}")
          @temp_path    ||= File.join(config['paths']['temp'],    "#{@id}")

          run("umount #{@target_path}")

          if options[:persistent]
            run("tar -zcf #{@temp_file} -C #{@image_path} .")
            run("curl -v -X PUT -H 'X-Appid: #{config['storage']['id']}' -T #{@temp_file} #{config['storage']['url']}/#{@appid}.tar.gz")
          end

          FileUtils.rm_rf(@image_path)
          FileUtils.rm_rf(@target_path)
          FileUtils.rm_rf(@temp_path)

          FileUtils.rm(@temp_file)
        end

        private

        def config
          Keeper.configuration
        end

        def run(command)
          Keeper.logger.debug('Aufs') { command }
          stdout = `#{command}`
          Keeper.logger.debug('Aufs') { stdout }
        end

      end
    end
  end
end
