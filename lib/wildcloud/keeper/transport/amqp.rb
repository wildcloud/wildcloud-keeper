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


require 'amqp'
require 'json'

require 'wildcloud/keeper/logger'
require 'wildcloud/keeper/configuration'

module Wildcloud
  module Keeper
    module Transport

      class Amqp

        def initialize
          Keeper.logger.debug('AMQP') { 'Connecting to broker' }

          @connection = AMQP.connect(Keeper.configuration['amqp'])
          Keeper.add_amqp_logger(@connection)

          @channel = AMQP::Channel.new(@connection)
          @channel.prefetch(Keeper.configuration['workers'])

          @exchange = @channel.topic('wildcloud.keeper')
          @queue = @channel.queue("wildcloud.keeper.node.#{Keeper.configuration['node']['name']}")
          @queue.bind(@exchange, :routing_key => 'nodes')
          @queue.bind(@exchange, :routing_key => "node.#{Keeper.configuration['node']['name']}")

          if Keeper.configuration['builder']
            @builders = @channel.queue("wildcloud.keeper.build")
            @builders.bind(@exchange, :routing_key => 'build')
          end
        end

        def start(&block)
          Keeper.logger.info('AMQP') { 'Starting to receive messages' }
          @subscription = @queue.subscribe do |metadata, payload|
            process_message(block, payload)
          end
          @building = @builders.subscribe do |metadata, payload|
            process_message(block, payload)
          end if @builders
        end

        def process_message(block, payload)
          block.call(JSON.parse(payload))
        end

        def send(message, key)
          Keeper.logger.debug('AMQP') { "Publishing message (key: #{key}) #{message.inspect}" }
          @exchange.publish(JSON.dump(message), :routing_key => key.to_s)
        end

      end
    end
  end
end
