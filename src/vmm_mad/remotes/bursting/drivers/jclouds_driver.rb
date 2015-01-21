#!/usr/bin/env ruby
# -------------------------------------------------------------------------- #
# Copyright 2015, Terradue S.r.l.                                            #
#                                                                            #
# Licensed under the Apache License, Version 2.0 (the "License"); you may    #
# not use this file except in compliance with the License. You may obtain    #
# a copy of the License at                                                   #
#                                                                            #
# http://www.apache.org/licenses/LICENSE-2.0                                 #
#                                                                            #
# Unless required by applicable law or agreed to in writing, software        #
# distributed under the License is distributed on an "AS IS" BASIS,          #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
# See the License for the specific language governing permissions and        #
# limitations under the License.                                             #
# -------------------------------------------------------------------------- #

require 'drivers/bursting_driver'

class JcloudsDriver < BurstingDriver

  DRIVER_CONF    = "#{ETC_LOCATION}/jclouds_driver.conf"
  DRIVER_DEFAULT = "#{ETC_LOCATION}/jclouds_driver.default"

  PUBLIC_TAG = "JCLOUDS"

  # Jclouds commands constants
  PUBLIC_CMD = {
    :run => {
      :cmd => :add,
      :args => {
        "HARDWAREID" => {
          :opt => '--hardwareid'
        },
        "IMAGEID" => {
          :opt => '--imageid'
        },
        "LOCATIONID" => {
          :opt => '--locationid'
        },
        "GROUP" => {
          :opt => '--group'
        },
      },
    },
    :get => {
      :cmd => :listnodes,
      :args => {
        "ID" => {
          :opt => '--id'
        },
      },
    },
    :shutdown => {
      :cmd => :destroy,
      :args => {
        "ID" => {
          :opt => '--id'
        },
      },
    },
    :reboot => {
      :cmd => :reboot
    },
    :stop => {
      :cmd => :destroy
    },
    :start => {
      :cmd => :start
    },
    :delete => {
      :cmd => :destroy
    }
  }

  # Jclouds attributes that will be retrieved in a polling action
  POLL_ATTRS = [
    :private_ip_address,
    :ip_address
  ]

  JCLOUDS_CMD = "/usr/lib/jclouds-cli/bin/jclouds-cli"

  def initialize(host)
    
    super(host)

    @instance_types = @public_cloud_conf['instance_types']
    
    regions = @public_cloud_conf['regions']
    @region = regions[host] || regions["default"]
    
    @args = ""
    # TODO get provider from public_cloud_conf
    provider = "aws-ec2"
    args.concat(" --provider #{provider}")
    args.concat(" --identity #{@region['access_key_id']}")
    args.concat(" --credential #{@region['secret_key_id']}")
    
  end

  def create_instance(opts)
    
    command = self.class::PUBLIC_CMD[:run][:cmd]

    opts.each {|k,v|
      @args.concat(" ")
      @args.concat("#{k} #{v}")
    }
    
    begin
      rc, info = do_command("#{JCLOUDS_CMD} #{command} #{@args}")
      
      if rc == true
        return info
      else
        raise "Error creating the instance"
      end
    rescue => e
      STDERR.puts e.message
        exit(-1)
    end

    # TODO Placeholder
    # parse(info)
    puts "instanceid"
  end

  # Retrieve the instance from the Cloud Provider
  def get_instance(id)
    
    command = self.class::PUBLIC_CMD[:get][:cmd]
    
    begin
      rc, info = do_command("#{JCLOUDS_CMD} #{command} #{@args}")
      
      if rc == true
        return info
      else
        raise "Instance #{id} does not exist"
      end
    rescue => e
      STDERR.puts e.message
        exit(-1)
    end
  end
  
  # Retrieve the VM information
  def parse_poll(instance)
    info =  "#{POLL_ATTRIBUTE[:usedmemory]}=0 " \
            "#{POLL_ATTRIBUTE[:usedcpu]}=0 " \
            "#{POLL_ATTRIBUTE[:nettx]}=0 " \
            "#{POLL_ATTRIBUTE[:netrx]}=0 "

    state = ""
    if !instance
      state = VM_STATE[:deleted]
    else
      state = case instance.deployment_status
      when "Running", "Starting"
        VM_STATE[:active]
      when "Suspended", "Stopping", 
        VM_STATE[:paused]
      else
        VM_STATE[:deleted]
      end
    end
    
    info << "#{POLL_ATTRIBUTE[:state]}=#{state} "

    POLL_ATTRS.map { |key|
      value = instance.send(key)
      if !value.nil? && !value.empty?
        if key.to_s.upcase == "TCP_ENDPOINTS" or
          key.to_s.upcase == "UDP_ENDPOINTS"
          value_str = format_endpoints(value)
        elsif value.kind_of?(Hash)
          value_str = value.inspect
        else
          value_str = value
        end

        info << "PUBLIC_#{key.to_s.upcase}=#{value_str.gsub("\"","")} "

      end
    }

    info
  end
  

private

  def do_command(cmd)
    rc = LocalCommand.run(cmd)

    if rc.code == 0
      return [true, rc.stdout]
    else
      STDERR.puts("Error executing: #{cmd} err: #{rc.stderr} out: #{rc.stdout}")
      return [false, rc.code]
    end
  end

end
