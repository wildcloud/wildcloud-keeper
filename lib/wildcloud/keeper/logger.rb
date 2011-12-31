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

require 'wildcloud/logger'
require 'wildcloud/logger/middleware/console'
require 'wildcloud/logger/middleware/amqp'
require 'wildcloud/logger/middleware/json'

require 'json'

module Wildcloud
  module Keeper

    def self.logger
      unless @logger
        @logger = Wildcloud::Logger::Logger.new
        @logger.application = 'wildcloud.keeper'
        @logger.add(Wildcloud::Logger::Middleware::Console)
      end
      @logger
    end

    def self.add_amqp_logger(amqp)
      @logger.add(Wildcloud::Logger::Middleware::Json)
      @topic = AMQP::Channel.new(amqp).topic('wildcloud.logger')
      @logger.add(Wildcloud::Logger::Middleware::Amqp, :exchange => @topic, :routing_key => 'wildcloud.keeper')
    end

  end
end
