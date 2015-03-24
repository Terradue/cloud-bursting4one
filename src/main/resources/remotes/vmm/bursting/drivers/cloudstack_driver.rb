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
require 'jsonpath'
require 'uri'

include REXML

class CloudStackDriver < BurstingDriver

  DRIVER_CONF    = "#{ETC_LOCATION}/cloudstack_driver.conf"
  DRIVER_DEFAULT = "#{ETC_LOCATION}/cloudstack_driver.default"

  # Commands constants
  PUBLIC_CMD = {
    :run => {
      :cmd => :deploy,
      :subcmd => :virtualmachine,
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
      :cmd    => :list,
      :subcmd => :virtualmachines,
    },
    :delete => {
      :cmd => :destroy,
      :subcmd => :virtualmachine,
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
    }
  }

  # Child driver specific attributes
  DRV_POLL_ATTRS = {
    :ipaddress     => POLL_ATTRS[:privateaddresses],
    :publicaddress => POLL_ATTRS[:publicaddresses]
  }

  def initialize(host)
    
    super(host)

    @cli_cmd        = @public_cloud_conf['cloudstack_cmd']
    @context_path   = @public_cloud_conf['context_path']
    @instance_types = @public_cloud_conf['instance_types']
    
    @hostname = host
    
    hosts = @public_cloud_conf['hosts']
    @host = hosts[host] || hosts["default"]
    
    @auth = "-c #{@host['config_file']}"
  end

  def create_instance(vm_id, opts, context_xml)
    
    cmd    = self.class::PUBLIC_CMD[:run][:cmd]
    subcmd = self.class::PUBLIC_CMD[:run][:subcmd]
    
    args = ""

    opts.each {|k,v|
      args.concat(" ")
      args.concat("#{k}=#{v}")
    }
    
    args.concat(" ")
    args.concat("displayname=one-#{vm_id}")
    
    begin
      rc, info = do_command("#{@cli_cmd} #{@auth} #{cmd} #{subcmd} #{args}")
      
      raise "Error creating the instance" if !rc
    rescue => e
      STDERR.puts e.message
        exit(-1)
    end
    
    # The context_id is one of the privateaddresses.
    # The safest solution is to create a context for all the privateaddresses 
    # associated to the vm.
    key = DRV_POLL_ATTRS.invert[POLL_ATTRS[:privateaddresses]]
    privateaddresses = JsonPath.on(info, "$..#{key}")
    
    privateaddresses.each { |privateaddress|
      create_context(context_xml, privateaddress.gsub(".", "-"))
    }

    return JsonPath.on(info, "$..displayname")[0]
  end
  
  def destroy_instance(deploy_id)
    
    cmd    = self.class::PUBLIC_CMD[:delete][:cmd]
    subcmd = self.class::PUBLIC_CMD[:delete][:subcmd]
    
    args = "id=#{deploy_id}"
    
    vm = get_instance(deploy_id)
  
    begin
      rc, info = do_command("#{@cli_cmd} #{@auth} #{cmd} #{subcmd} #{args}")
      
      raise "Instance #{id} does not exist" if !rc
      
      # The context_id is one of the privateaddresses.
      # The safest solution is to check and remove all the privateaddresses 
      # associated to the vm.    
      key = DRV_POLL_ATTRS.invert[POLL_ATTRS[:privateaddresses]]
      privateaddresses = JsonPath.on(vm, "$..#{key}")
      
      privateaddresses.each { |privateaddress|
        remove_context(privateaddress.gsub(".", "-"))
      }

    rescue => e
      STDERR.puts e.message
      exit(-1)
    end

    return info
  end
  
  def get_instance(deploy_id)
    
    cmd    = self.class::PUBLIC_CMD[:get][:cmd]
    subcmd = self.class::PUBLIC_CMD[:get][:subcmd]
    
    args = "id=#{deploy_id}"

    begin
      rc, info = do_command("#{@cli_cmd} #{@auth} #{cmd} #{subcmd} #{args}")
      
      raise "Instance #{id} does not exist" if !rc
    rescue => e
      STDERR.puts e.message
      exit(-1)
    end
    
    instance = JSON.parse(info)
    return instance['virtualmachine'][0]
  end

  def monitor_all_vms(host_id)
    
    cmd    = self.class::PUBLIC_CMD[:get][:cmd]
    subcmd = self.class::PUBLIC_CMD[:get][:subcmd]
        
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
    
    rc, info = do_command("#{@cli_cmd} #{@auth} #{cmd} #{subcmd}")
    
    if !info.empty?
      instance = JSON.parse(info)
    
      # For each instance 'virtualmachine'
      instance['virtualmachine'].each { |vm|
        next if vm["state"] != :pending && vm["state"] != :running
        
        poll_data = parse_poll(vm)
        
        deploy_id = vm["displayname"]
        vm_id = deploy_id.match(/one-(.*)/)[1]
        
        vms_info << "VM=[\n"
                  vms_info << "  ID=#{vm_id || -1},\n"
                  vms_info << "  DEPLOY_ID=#{deploy_id},\n"
                  vms_info << "  POLL=\"#{poll_data}\" ]\n"
      }
    end
    
    puts host_info
    puts vms_info
  end

  def parse_poll(vm)
    
    begin
      info =  "#{POLL_ATTRIBUTE[:usedmemory]}=0 " \
              "#{POLL_ATTRIBUTE[:usedcpu]}=0 " \
              "#{POLL_ATTRIBUTE[:nettx]}=0 " \
              "#{POLL_ATTRIBUTE[:netrx]}=0 "

      state = ""
      if !vm
        state = VM_STATE[:deleted]
      else
        state = case vm['state']
        when "Running", "Starting"
          VM_STATE[:active]
        when "Suspended", "Stopping", 
          VM_STATE[:paused]
        else
          VM_STATE[:deleted]
        end
      end
    
      info << "#{POLL_ATTRIBUTE[:state]}=#{state} "
    
      # Search for the value(s) corresponding to the DRV_POLL_ATTRS keys
      DRV_POLL_ATTRS.map { |key, value|
        results = JsonPath.on(vm, "$..#{key}")
        if results.length > 0
          results.join(",")
          info << "CLOUDSTACK_#{value.to_s.upcase}=#{URI::encode(results.join(","))} "
        end  
      }
    
      info
    rescue
      # Unkown state if exception occurs retrieving information from
      # an instance
      STDERR.puts e.message
      "#{POLL_ATTRIBUTE[:state]}=#{VM_STATE[:unknown]} "
    end
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
