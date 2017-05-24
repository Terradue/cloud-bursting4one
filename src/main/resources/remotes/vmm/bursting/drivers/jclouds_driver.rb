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

class JcloudsDriver < BurstingDriver

  DRIVER_CONF    = "#{ETC_LOCATION}/jclouds_driver.conf"
  DRIVER_DEFAULT = "#{ETC_LOCATION}/jclouds_driver.default"

  # Commands constants
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

  # CLI specific attributes that will be retrieved in a polling action
  POLL_ATTRS = [
    :publicAddresses,
    :privateAddresses
  ]

  def initialize(host)
    super(host)

    @cli_cmd    = @public_cloud_conf['jclouds_cmd']
    @context_path   = @public_cloud_conf['context_path']
    @instance_types = @public_cloud_conf['instance_types']
    
    @hostname = host
    
    hosts = @public_cloud_conf['hosts']
    @host = hosts[host] || hosts["default"]
    
    @context_path.concat("/#{@host['provider']}/")
    
    @common_args = ""
    @common_args.concat(" --provider #{@host['provider']}")
    @common_args.concat(" --identity #{@host['identity']}")
    @common_args.concat(" --credential #{@host['credential']}")
    
    if @host['endpoint']
      @common_args.concat(" --endpoint #{@host['endpoint']}")
    end
    
  end

  def create_instance(vm_id, opts, context_xml)
    command = self.class::PUBLIC_CMD[:run][:cmd]
    
    # Here we can just put this additional information into the CONTEXT part,
    # not the PUBLIC_CLOUD one, because the generic 'add' command doesn't have
    # these additional parameters.
    floating_ip = value_from_xml(context_xml[0],"FLOATING_IP")
    storage_size = value_from_xml(context_xml[0],"STORAGE_SIZE")
    
    args = @common_args.clone

    opts.each {|k,v|
      args.concat(" ")
      args.concat("#{k} #{v}")
    }
    
    log("#{LOG_LOCATION}/#{vm_id}.log","create","Start deploying one-#{vm_id}")
    
    begin
      rc, info = do_command("#{@cli_cmd} #{command} #{args}")
      
      raise "Error creating the instance" if !rc
    rescue => e
      STDERR.puts e.message
        exit(-1)
    end
    
    log("#{LOG_LOCATION}/#{vm_id}.log","create","Compute #{deploy_id} created")
    
    # TODO manage the case of multiple addresses
    context_id = JSON.parse(info)['privateAddresses'].gsub(".", "-")
    
    create_context(context_xml, context_id)
    
    # This part is specific for the openstack-nova provider.
    # They are workarounds, since they're not generic operations.
    # ==========================================================================
    if floating_ip
      log("#{LOG_LOCATION}/#{vm_id}.log","create","Attaching a floating IP")
      
      deploy_id = JSON.parse(info)['id']
      command = "createattachfloatingip"
      
      region = value_from_xml(context_xml[0],"REGION")
      pool = value_from_xml(context_xml[0],"POOL")
      server_id = deploy_id.match(/#{region}\/(.*)/)[1]
      
      args = @common_args.clone
    
      args.concat(" --serverid #{server_id}")
      args.concat(" --region #{region}")
      args.concat(" --pool #{pool}")
      
      begin
        rc, info = do_command("#{@cli_cmd} #{command} #{args}")
      
        raise "Error attaching the IP" if !rc
      rescue => e
        STDERR.puts e.message
        destroy_instance(deploy_id)
        exit(-1)
      end
      
      log("#{LOG_LOCATION}/#{vm_id}.log","create","Floating IP attached")
      
    end
    
    if storage_size
      log("#{LOG_LOCATION}/#{vm_id}.log","create","Creating additional storage of #{storage_size} GB")
      
      deploy_id = JSON.parse(info)['id']
      command = "createattachvolume"
      
      region = value_from_xml(context_xml[0],"REGION")
      device = value_from_xml(context_xml[0],"DEVICE")
      server_id = deploy_id.match(/#{region}\/(.*)/)[1]
      
      args = @common_args.clone
    
      args.concat(" --serverid #{server_id}")
      args.concat(" --region #{region}")
      args.concat(" --device #{device}")
      args.concat(" --name #{vm_id}")
      args.concat(" --size #{storage_size}")
      
      begin
        rc, info = do_command("#{@cli_cmd} #{command} #{args}")
      
        raise "Error attaching the storage" if !rc
      rescue => e
        STDERR.puts e.message
        destroy_instance(deploy_id)
        exit(-1)
      end
    end
    # ==========================================================================
    
    log("#{LOG_LOCATION}/#{vm_id}.log","create","Deploy one-#{vm_id} completed")

    return JSON.parse(info)['id']
  end

  def get_instance(deploy_id)
    
    command = self.class::PUBLIC_CMD[:get][:cmd]
    
    args = @common_args.clone
    
    args.concat(" --id #{deploy_id}")

    begin
      rc, info = do_command("#{@cli_cmd} #{command} #{args}")
      
      raise "Instance #{id} does not exist" if !rc
    rescue => e
      STDERR.puts e.message
        exit(-1)
    end

    return info
  end
  
  def destroy_instance(deploy_id)
    command = self.class::PUBLIC_CMD[:delete][:cmd]
    
    info = get_instance(deploy_id)
    
    # TODO manage the case of multiple addresses
    context_id = JSON.parse(info)['privateAddresses'].gsub(".", "-")
    
    args = @common_args.clone
    
    args.concat(" --id #{deploy_id}")

    begin
      rc, info = do_command("#{@cli_cmd} #{command} #{args}")
      
      raise "Instance #{id} does not exist" if !rc
      
      remove_context(context_id)
      
    rescue => e
      STDERR.puts e.message
        exit(-1)
    end

    return info
  end

  def monitor_all_vms(host_id)
    totalmemory = 0
    totalcpu = 0
    @host['capacity'].each { |name, size|
      cpu, mem = instance_type_capacity(name)

      totalmemory += mem * size.to_i
      totalcpu    += cpu * size.to_i
    }

    host_info =  "HYPERVISOR=jclouds\n"
    host_info << "PUBLIC_CLOUD=YES\n"
    host_info << "PRIORITY=-1\n"
    host_info << "TOTALMEMORY=#{totalmemory.round}\n"
    host_info << "TOTALCPU=#{totalcpu}\n"
    host_info << "CPUSPEED=1000\n"
    host_info << "HOSTNAME=\"#{@hostname}\"\n"

    vms_info = "VM_POLL=YES\n"

    client = ::OpenNebula::Client.new()

    xml = client.call("host.info",host_id.to_i)
    xml_host = REXML::Document.new(xml) if xml

    usedcpu    = 0
    usedmemory = 0
    
    # In the case of the jclouds driver is not possible to assign a name
    # or a TAG to the VM. In this way a VM started from the OpenNebula cannot
    # be discriminated from one started from another client. 
    # The solution here is to perform a polling call for each VM.
    # The OpenNebula's XML-RPC Api is used to get all the instances associated
    # with the 'host_id' specified.

    XPath.each(xml_host, "/HOST/VMS/ID") { |e1|
      vm_id = e1.text

      xml = client.call("vm.info", vm_id.to_i)
      xml_vm = REXML::Document.new(xml) if xml

      deploy_id = ""
      poll_data = ""
      
      XPath.each(xml_vm, "/VM/DEPLOY_ID") { |e2| deploy_id = e2.text }

      if !deploy_id.nil?
        if !deploy_id.empty?
          instance = get_instance(deploy_id)
          poll_data = parse_poll(instance)
 
          vms_info << "VM=[\n"
                    vms_info << "  ID=#{vm_id || -1},\n"
                    vms_info << "  DEPLOY_ID=#{deploy_id},\n"
                    vms_info << "  POLL=\"#{poll_data}\" ]\n"
        end
      end

    }

    puts host_info
    puts vms_info
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

	# TODO: In the case of _PUBLICADDRESSES or _PRIVATEADDRESSES keys, handle the case in which multiple addresses are passed.
	# Use comma-separated list (e.g., interface to E-CEO portal)
        info << "JCLOUDS_#{key.to_s.upcase}=#{value_str.gsub("\"","")} "

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
