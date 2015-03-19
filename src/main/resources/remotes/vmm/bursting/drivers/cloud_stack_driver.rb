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

include REXML

class CloudStackDriver < BurstingDriver

  DRIVER_CONF    = "#{ETC_LOCATION}/cloudstack_driver.conf"
  DRIVER_DEFAULT = "#{ETC_LOCATION}/cloudstack_driver.default"

  # Commands constants
  PUBLIC_CMD = {
    :run => {
      :cmd => :deploy,
      :args => {
        "ZONEID" => {
          :opt => 'zoneid'
        },
        "TEMPLATEID" => {
          :opt => 'templateid'
        },
        "SERVICEOFFERINGID" => {
          :opt => 'serviceofferingid'
        },
      },
    },
    :get => {
      :cmd =>  :list,
      :args => :virtualmachines,
    },
    :shutdown => {
      :cmd => :destroy,
      :args => {
        "ID" => {
          :opt => 'id'
        },
      },
    },
    :reboot => {
      :cmd => :reboot
    },
    :stop => {
      :cmd => :stop
    },
    :start => {
      :cmd => :start
    },
    :delete => {
      :cmd => :destroy
    }
  }

  # CLI specific attributes that will be retrieved in a polling action
  POLL_ATTRS = [
    :publicAddresses,
    :privateAddresses,
    :displayname
  ]

  def initialize(host)
    super(host)

    @cli_cmd     = @public_cloud_conf['cloudstack_cmd']
    @context_path   = @public_cloud_conf['context_path']
    @instance_types = @public_cloud_conf['instance_types']
    
    @hostname = host
    
    hosts = @public_cloud_conf['hosts']
    @host = hosts[host] || hosts["default"]
    
    @auth = " -c #{@host['config_file']}"
  end

  def create_instance(opts, context_xml)
    command = self.class::PUBLIC_CMD[:run][:cmd]
    
    args = @common_args.clone

    opts.each {|k,v|
      args.concat(" ")
      args.concat("#{k} #{v}")
    }
    
    begin
      rc, info = do_command("#{@cli_cmd} #{command} #{args}")
      
      raise "Error creating the instance" if !rc
    rescue => e
      STDERR.puts e.message
        exit(-1)
    end
    
    # Set also 'displayname' attribute using the OpenNebula ID
    
    # TODO manage the case of multiple addresses
    context_id = JSON.parse(info)['publicAddresses'].gsub(".", "-")
    
    create_context(context_xml, context_id, @context_path)

    return JSON.parse(info)['id']
  end
  
  def destroy_instance(deploy_id)
    command = self.class::PUBLIC_CMD[:delete][:cmd]
    
    info = get_instance(deploy_id)
    
    # TODO manage the case of multiple addresses
    context_id = JSON.parse(info)['publicAddresses'].gsub(".", "-")
    
    args = @common_args.clone
    
    args.concat(" --id #{deploy_id}")

    begin
      rc, info = deploy_ido_command("#{@cli_cmd} #{command} #{args}")
      
      raise "Instance #{id} does not exist" if !rc
      
      remove_context(context_id, @context_path)
      
    rescue => e
      STDERR.puts e.message
        exit(-1)
    end

    return info
  end

  def monitor_all_vms(host_id)
    command = self.class::PUBLIC_CMD[:get][:cmd]
    args = self.class::PUBLIC_CMD[:get][:args]
        
    totalmemory = 0
    totalcpu = 0
    @host['capacity'].each { |name, size|
      cpu, mem = instance_type_capacity(name)

      totalmemory += mem * size.to_i
      totalcpu    += cpu * size.to_i
    }

    host_info =  "HYPERVISOR=cloudstack\n"
    host_info << "PUBLIC_CLOUD=YES\n"
    host_info << "PRIORITY=-1\n"
    host_info << "TOTALMEMORY=#{totalmemory.round}\n"
    host_info << "TOTALCPU=#{totalcpu}\n"
    host_info << "CPUSPEED=1000\n"
    host_info << "HOSTNAME=\"#{@hostname}\"\n"

    vms_info = "VM_POLL=YES\n"

    usedcpu    = 0
    usedmemory = 0
    
    rc, info = do_command("#{@cli_cmd} #{@auth} #{command} #{args}")
    poll_data = parse_poll(info) if !info.empty?
 
    # To iterate over poll data
    #vms_info << "VM=[\n"
    #          vms_info << "  ID=#{vm_id || -1},\n"
    #          vms_info << "  DEPLOY_ID=#{deploy_id},\n"
    #          vms_info << "  POLL=\"#{poll_data}\" ]\n"

    puts poll_data
    puts host_info
    #puts vms_info
  end

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
      state = case instance['state']
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

        info << "CLOUDSTACK_#{key.to_s.upcase}=#{value_str.gsub("\"","")} "

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
