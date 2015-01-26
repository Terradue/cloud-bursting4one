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
require 'opennebula'

include OpenNebula
include REXML

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
    :publicAddresses,
    :privateAddresses
  ]

  JCLOUDS_CMD = "/usr/lib/jclouds-cli/bin/jclouds-cli"

  def initialize(host)
    
    super(host)

    @instance_types = @public_cloud_conf['instance_types']
    
    hosts = @public_cloud_conf['hosts']
    @host = hosts[host] || hosts["default"]
    
    @args = ""
    @args.concat(" --provider #{@host['provider']}")
    @args.concat(" --identity #{@host['identity']}")
    @args.concat(" --credential #{@host['credential']}")
    
  end

  def create_instance(opts)
    
    command = self.class::PUBLIC_CMD[:run][:cmd]

    opts.each {|k,v|
      @args.concat(" ")
      @args.concat("#{k} #{v}")
    }
    
    begin
      rc, info = do_command("#{JCLOUDS_CMD} #{command} #{@args}")
      
      raise "Error creating the instance" if !rc
    rescue => e
      STDERR.puts e.message
        exit(-1)
    end

    return JSON.parse(info)['id']

  end

  # Retrieve the instance from the Cloud Provider
  def get_instance(id)
    
    command = self.class::PUBLIC_CMD[:get][:cmd]
    
    @args.concat(" --id #{id}")

    begin
      rc, info = do_command("#{JCLOUDS_CMD} #{command} #{@args}")
      
      raise "Instance #{id} does not exist" if !rc
    rescue => e
      STDERR.puts e.message
        exit(-1)
    end

    return info
  end
  
  # Destroy the instance from the Cloud Provider
  def destroy_instance(id)
    
    command = self.class::PUBLIC_CMD[:delete][:cmd]
    
    @args.concat(" --id #{id}")

    begin
      rc, info = do_command("#{JCLOUDS_CMD} #{command} #{@args}")
      
      raise "Instance #{id} does not exist" if !rc
    rescue => e
      STDERR.puts e.message
        exit(-1)
    end

    return info
  end

  def monitor_all_vms

    totalmemory = 0
    totalcpu = 0
    @host['capacity'].each { |name, size|
      cpu, mem = instance_type_capacity(name)

      totalmemory += mem * size.to_i
      totalcpu    += cpu * size.to_i
    }

    host_info =  "HYPERVISOR=bursting\n"
    host_info << "PUBLIC_CLOUD=YES\n"
    host_info << "PRIORITY=-1\n"
    host_info << "TOTALMEMORY=#{totalmemory.round}\n"
    host_info << "TOTALCPU=#{totalcpu}\n"
    host_info << "CPUSPEED=1000\n"
    host_info << "HOSTNAME=\"#{@host}\"\n"

    vms_info = "VM_POLL=YES\n"

    # In tha case of the jclouds driver is not possible to assign a name
    # to the VM or assign a tag, as in the case of EC2 client
    one_auth = File.read(DEFAULT_AUTH_FILE)

    rpc_client = Client.new(one_auth, DEFAULT_ENDPOINT)

    host = Host.new(Host.build_xml(76),rpc_client)

    xmldoc = Document.new(host.monitoring_xml)
  
    XPath.each(xmldoc, "//HOST[last()]/VMS/ID") { |e| 
    }

    puts host_info
    puts vms_info

  end
  
  # Retrieve the VM information
  def parse_poll(instance_info)
    info =  "#{POLL_ATTRIBUTE[:usedmemory]}=0 " \
            "#{POLL_ATTRIBUTE[:usedcpu]}=0 " \
            "#{POLL_ATTRIBUTE[:nettx]}=0 " \
            "#{POLL_ATTRIBUTE[:netrx]}=0 "

    instance = JSON.parse(instance_info)

    state = ""
    if !instance
      state = VM_STATE[:deleted]
    else
      state = case instance['status']
      when "RUNNING", "STARTING"
        VM_STATE[:active]
      when "SUSPENDED", "STOPPING", 
        VM_STATE[:paused]
      else
        VM_STATE[:deleted]
      end
    end
    
    info << "#{POLL_ATTRIBUTE[:state]}=#{state} "

    POLL_ATTRS.map { |key|
      value = instance["#{key}"]
      if !value.nil? && !value.empty?
        if value.kind_of?(Hash)
          value_str = value.inspect
        else
          value_str = value
        end

        info << "PUBLIC_#{key.to_s.upcase}=#{value_str.gsub("\"","")} "

      end
    }

    return info

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
