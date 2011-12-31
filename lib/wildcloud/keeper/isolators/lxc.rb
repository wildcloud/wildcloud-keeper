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
require 'erb'

require 'wildcloud/keeper/configuration'
require 'wildcloud/keeper/logger'

module Wildcloud
  module Keeper
    module Isolators
      class Lxc

        def start(options)

          @id = options[:id]
          @target_path = File.join(config['paths']['mounts'], "#{@id}")

          @config_file = File.join(config['paths']['config'], "#{@id}.config")
          @fstab_file = File.join(config['paths']['config'], "#{@id}.fstab")

          vm_config = ERB.new(File.read(File.expand_path('../../templates/app.config', __FILE__))).result(binding)
          vm_fstab = ERB.new(File.read(File.expand_path('../../templates/app.fstab', __FILE__))).result(binding)

          FileUtils.mkdir_p(config['paths']['config'])

          File.open(@config_file, 'w') { |file| file.write(vm_config) }
          File.open(@fstab_file, 'w') { |file| file.write(vm_fstab) }

          run("lxc-create -f #{@config_file} -n #{@id}")
          run("lxc-start -d -n #{@id}")

        end

        def stop(options)

          @id ||= options[:id]
          @config_file ||= File.join(config['paths']['config'], "#{@id}.config")
          @fstab_file ||= File.join(config['paths']['config'], "#{@id}.fstab")


          if options[:build]
            build_status_file = File.join(config['paths']['images'], "#{@id}", 'var', 'build.done')
            until File.exists?(build_status_file)
              sleep(5)
            end
          end

          run("lxc-stop -n #{@id}")
          run("lxc-destroy -n #{@id}")

          FileUtils.rm(@config_file)
          FileUtils.rm(@fstab_file)
        end

        def resources(options)

          @id ||= options[:id]

          run("lxc-cgroup -n #{@id} memory.limit_in_bytes \"#{options[:memory]}\"") if options[:memory]
          run("lxc-cgroup -n #{@id} memory.memsw.limit_in_bytes \"#{options[:swap]}\"") if options[:swap]
          run("lxc-cgroup -n #{@id} cpuset.cpus \"#{options[:cpus]}\"") if options[:cpus]
          run("lxc-cgroup -n #{@id} cpu.shares \"#{options[:cpu_share]}\"") if options[:cpu_share]
        end

        private

        def config
          Keeper.configuration
        end

        def run(command)
          Keeper.logger.debug('LXC') { command }
          stdout = `#{command}`
          Keeper.logger.debug('LXC') { stdout }
        end

      end
    end
  end
end
