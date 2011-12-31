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
require 'thread'
require 'yaml'

require 'wildcloud/keeper/logger'
require 'wildcloud/keeper/configuration'

require 'wildcloud/keeper/isolators/lxc'
require 'wildcloud/keeper/deployers/aufs'

require 'wildcloud/keeper/transport/amqp'

module Wildcloud
  module Keeper
    class Runtime

      def initialize
        @repository = {}

        Keeper.logger.info('Runtime') { 'Starting transport' }
        @transport = Transport::Amqp.new

        Keeper.logger.info('Runtime') { 'Starting thread-pool' }
        @queue = Queue.new
        @thread_pool = []

        Keeper.configuration['node']['workers'].times do |i|
          Keeper.logger.debug('Runtime', "Starting thread ##{i}")
          Thread.new(i) do |id|
            Thread.current.abort_on_exception = false
            loop do
              Keeper.logger.debug('Runtime') { "Thread ##{id} waiting for task" }
              begin
                @queue.pop.call
              rescue Exception => exception
                Keeper.logger.fatal('Runtime') { "Exception in thread #{id}: #{exception.message}" }
                Keeper.logger.debug('Runtime') { exception }
                Keeper.logger.debug('Runtime') { exception.backtrace }
              else
                Keeper.logger.debug('Runtime') { "Thread ##{id} handled task successfully" }
              end
            end
          end
        end

        handler = self.method(:handle)
        @transport.start(&handler)
        @transport.send({:type => :sshkey, :node => Keeper.configuration['node']['name'], :key => File.read(File.expand_path('~/.ssh/id_rsa.pub')).strip}, :master)
        heartbeat
      end

      def heartbeat
        @transport.send({:type => 'heartbeat', :node => Keeper.configuration['node']['name']}, :master)
        EM.add_timer(5, method(:heartbeat))
      end

      def handle(message)
        Keeper.logger.debug('Runtime') { "Message received #{message.inspect}" }
        method = "handle_#{message['type']}".to_sym
        scope = self
        @queue << proc do
          scope.send(method, message)
        end
      rescue Exception => exception
        Keeper.logger.fatal('Runtime') { "Exception in runtime: #{exception.message}" }
        Keeper.logger.fatal(exception)
      end

      def handle_build(message)
        handle_deploy(message)
        handle_undeploy(message)
      end

      def instance(id, message)
        unless @repository[id]
          @repository[id] = {:isolator => Isolators::Lxc.new, :deployer => Deployers::Aufs.new}
          @repository[id][:options] = {
              :id => "instance_#{message['id']}",
              :appid => message['appid'],
              :base_image => message['image'],
              :persistent => message['persistent'],
              :ip_address => message['ip_address'],
              :memory => message['memory'],
              :swap => message['swap'],
              :cpus => message['cpus'],
              :cpu_share => message['cpu_share']
          }
          if message['type'] == 'build'
            @repository[id][:options].merge!({
                :id => "build_#{message['id']}",
                :persistent => true,
                :build => true,
                :repository => message['repository'],
                :revision => message['revision']
            })
          end
        end
        @repository[id]
      end

      def get_instance_name(message)
        message['type'] == 'build' ? "build_#{message['id']}" : "instance_#{message['id']}"
      end

      def get_instance(message)
        instance = instance(get_instance_name(message), message)
        options = instance[:options]
        [instance, options]
      end

      def handle_deploy(message)
        instance, options = get_instance(message)
        instance[:deployer].deploy(options)
        write_system_configuration(options)
        instance[:isolator].start(options)
        unless options[:build]
          @transport.send({:type => :deployed, :node => Keeper.configuration['node']['name'], :id => message['id']}, :master)
        end
      end

      def handle_undeploy(message)
        instance, options = get_instance(message)
        instance[:isolator].stop(options)
        clean_system_configuration(options)
        if options[:build]
          build_log = File.read(File.join(options[:root_path], 'var', 'build.log'))
        end
        instance[:deployer].undeploy(options)
        if options[:build]
          @transport.send({:type => :build_log, :node => Keeper.configuration['node']['name'], :id => message['id'], :content => build_log}, :master)
        else
          @transport.send({:type => :undeployed, :node => Keeper.configuration['node']['name'], :id => message['id']}, :master)
        end
      end

      def handle_resources(message)
        instance_name = get_instance_name(message)
        instance = @repository[instance_name]
        unless instance
          return
        end
        options = instance[:options]
        options[:memory] = message['memory']
        options[:swap] = message['swap']
        options[:cpus] = message['cpus']
        options[:cpu_share] = message['cpu_share']
        instance[:isolator].resources(options)
      end

      def write_system_configuration(options)
        root = options[:root_path]

        interfaces = ERB.new(File.read(File.expand_path('../templates/interfaces', __FILE__))).result(binding)
        interfaces_path = File.join(root, 'etc', 'network', 'interfaces')
        FileUtils.mkdir_p(File.dirname(interfaces_path))
        File.open(interfaces_path, 'w') { |file| file.write(interfaces) }

        if options[:build]
          FileUtils.mkdir_p(File.join(root, 'root', '.ssh'))
          FileUtils.cp(File.expand_path('~/.ssh/id_rsa'), File.join(root, 'root', '.ssh', 'id_rsa'))
          FileUtils.cp(File.expand_path('~/.ssh/id_rsa.pub'), File.join(root, 'root', '.ssh', 'id_rsa.pub'))

          File.open(File.join(root, 'root', 'build.yml'), 'w') { |file| file.write(YAML::dump(options)) }
        end
      end

      def clean_system_configuration(options)
        root = options[:root_path]

        if options[:build]
          FileUtils.rm_rf(File.join(root, 'root', '.ssh'))
        end
      end

      def handle_quit
        Keeper.logger.fatal('Runtime') { "Shutdown requested." }
        EventMachine.stop_event_loop
      end

    end
  end
end
