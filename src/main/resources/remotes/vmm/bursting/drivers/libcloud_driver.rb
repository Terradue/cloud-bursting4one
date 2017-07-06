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

require 'time'
require 'timeout'
require 'drivers/bursting_driver'

include REXML

class LibcloudDriver < BurstingDriver
  
  DRIVER_CONF    = "#{ETC_LOCATION}/libcloud_driver.conf"
  DRIVER_DEFAULT = "#{ETC_LOCATION}/libcloud_driver.default"

  # Commands constants
  PUBLIC_CMD = {
    :run => {
      :cmd => :'create-node',
      :args => {
        "HARDWAREID" => {
          :opt => '--flavorId'
        },
        "IMAGEID" => {
          :opt => '--image'
        },
#        "GROUP" => {
#          :opt => '--group'
#        },
        "NETWORKS" => {
          :opt => '--networks'
        },
        "POOL" => {
          :opt => '--floatingippool'
        }
      },
    },
    :get => {
      :cmd => 'find-node',
      :args => {
        "ID" => {
          :opt => '--id'
        },
      },
    },
    :shutdown => {
      :cmd => 'destroy-node',
      :args => {
        "ID" => {
          :opt => '--id'
        },
      },
    }
  }

  # CLI specific attributes that will be retrieved in a polling action
  POLL_ATTRS = [
    :public_ips,
    :private_ips
  ]

  def initialize(host)
    super(host)

    @cli_cmd    = @public_cloud_conf['libcloud_cmd']
    @context_path   = @public_cloud_conf['context_path']
    @instance_types = @public_cloud_conf['instance_types']
    
    @hostname = host
    
    hosts = @public_cloud_conf['hosts']
    @host = hosts[host] || hosts["default"]
    
    @context_path.concat("/#{@host['provider']}/")
    
    @common_args = ""
    @common_args.concat("--provider \'#{@host['provider']}\'")
    @common_args.concat(" --user \'#{@host['user']}\'")
    @common_args.concat(" --key \'#{@host['key']}\'")
    @common_args.concat(" --ex_force_auth_version \'#{@host['ex_force_auth_version']}\'")
    @common_args.concat(" --ex_force_auth_url \'#{@host['ex_force_auth_url']}\'")
    @common_args.concat(" --ex_force_base_url \'#{@host['ex_force_base_url']}\'")
    @common_args.concat(" --ex_domain_name \'#{@host['ex_domain_name']}\'")
    @common_args.concat(" --ex_token_scope \'#{@host['ex_token_scope']}\'")
    @common_args.concat(" --ex_tenant_name \'#{@host['ex_tenant_name']}\'")
    @common_args.concat(" --json")
    

  end


  def create_instance(vm_id, opts, context_xml)

    log("#{LOG_LOCATION}/#{vm_id}.log","info","creating instance")
    command = self.class::PUBLIC_CMD[:run][:cmd]
    
    args = @common_args.clone

    opts.each {|k,v|
      args.concat(" ")
      args.concat("#{k} \'#{v}\'")
    }
    
    begin
      log("#{LOG_LOCATION}/#{vm_id}.log","info","#{@cli_cmd} #{command} #{args} --name \'one_#{vm_id}\' 2>/dev/null")
      rc, info = do_command("#{@cli_cmd} #{command} #{args} --name \'one-#{vm_id}\' 2>/dev/null")

      log("#{LOG_LOCATION}/#{vm_id}.log","info","info: #{JSON.parse(info).to_s}")
      nodeId = JSON.parse(info)['data'][0]['id']
      log("#{LOG_LOCATION}/#{vm_id}.log","info","nodeid is #{nodeId.to_s}")
      privateAddresses = JSON.parse(info)['data'][0]['private_ips']     
       
      log("#{LOG_LOCATION}/#{vm_id}.log","info","privateAddresses is #{privateAddresses}")

      # while the node is not running
      # timeout is set to 5 minutes
      timeout_in_seconds = 5*60
      Timeout.timeout(timeout_in_seconds) do
        while privateAddresses.nil? || privateAddresses.empty?  do
          log("#{LOG_LOCATION}/#{vm_id}.log","info","waiting for the node to run")
          rc, info = do_command("#{@cli_cmd} find-node #{args} --id \'#{nodeId}\' 2>/dev/null")
          privateAddresses = JSON.parse(info)['data'][0]['private_ips']
        end
      end

      raise "Error creating the instance" if !rc
    rescue => e
       log("#{LOG_LOCATION}/#{vm_id}.log","error", "### ERROR\n An error occured " + e.message)
      STDERR.puts e.message
        exit(-1)
    end
    
    privateAddresses.each { |ip|
      context_id = ip.gsub(".", "-") 
      create_context(context_xml, context_id) 
    }

    log("#{LOG_LOCATION}/#{vm_id}.log","info","returning nodeid #{nodeId}")
    
    return nodeId
  end


  def get_instance(deploy_id)
    log("#{LOG_LOCATION}/#{vm_id}.log","info","get_instance\n #{deploy_id.to_s}") 
    command = self.class::PUBLIC_CMD[:get][:cmd]
    
    args = @common_args.clone
    
    args.concat(" --id #{deploy_id}")

    begin
      rc,info = do_command("#{@cli_cmd} #{command} #{args} 2>/dev/null")
      raise "Instance #{deploy_id} does not exist" if JSON.parse(info)['message'] 
    rescue => e
      STDERR.puts e.message
        exit(-1)
    end

    return info
  end
 

  def destroy_instance(deploy_id)

    log("#{LOG_LOCATION}/#{vm_id}.log","info","destroy_instance\n #{deploy_id.to_s}")

    command = self.class::PUBLIC_CMD[:shutdown][:cmd]
    
    info = get_instance(deploy_id)
    
    args = @common_args.clone
    
    args.concat(" --id #{deploy_id}")

    begin
      rc = do_command("#{@cli_cmd} #{command} #{args} 2>/dev/null")
     
      hash = JSON.parse(info)
      hash['data'][0]['state']='deleted'
      info = hash.to_json

      log("#{LOG_LOCATION}/#{vm_id}.log","info","info: #{info}\nreturn code: #{rc}") 
      raise "Instance #{id} does not exist" if !rc
  
      privateAddresses = JSON.parse(info)['data'][0]['private_ips'] 
      privateAddresses.each { |ip|
              context_id = ip.gsub(".", "-")
              remove_context(context_id)
      }

      volumesAttached = JSON.parse(info)['data'][0]['extra']['volumes_attached']
      
      if volumesAttached
        # while the node is running
        # timeout is set to 5 minutes
        timeout_in_seconds = 5*60
        Timeout.timeout(timeout_in_seconds) do
          loop do
            log("#{LOG_LOCATION}/#{vm_id}.log","info","waiting for the node to die")
            rc, info = do_command("#{@cli_cmd} find-node #{args} --id \'#{deploy_id}\' 2>/dev/null")
            break if JSON.parse(info)['message']
            log("#{LOG_LOCATION}/#{vm_id}.log","info","info: #{JSON.parse(info)['message'].to_s}")
          end
        end

        for volume in volumesAttached do
          log("#{LOG_LOCATION}/#{vm_id}.log","info","destroying volume: #{volume['id'].to_s}  \n #{@cli_cmd} destroy-volume #{@common_args} -v \'#{volume['id'].to_s}\' 2>/dev/null")
          rc,info = do_command("#{@cli_cmd} destroy-volume #{@common_args} -v \'#{volume['id'].to_s}\' ")
          raise "An error occured while destroying volume #{volume['id'].to_s} message: #{JSON.parse(info)['message']}" if !rc
          log("#{LOG_LOCATION}/#{vm_id}.log","info","volume #{volume['id'].to_s} #{JSON.parse(info)['message'].to_s} destroyed")
        end 
      end
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

    host_info =  "HYPERVISOR=libcloud\n"
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

    usedcpu    = 100
    usedmemory = 0
    
    # In the case of the libcloud driver is not possible to assign a name
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

    log("#{LOG_LOCATION}/#{vm_id}.log","info","parse_poll\n #{instance_info.to_s}")

    info =  "#{POLL_ATTRIBUTE[:usedmemory]}=0 " \
            "#{POLL_ATTRIBUTE[:usedcpu]}=0 " \
            "#{POLL_ATTRIBUTE[:nettx]}=0 " \
            "#{POLL_ATTRIBUTE[:netrx]}=0 "

    instance = JSON.parse(instance_info)

    state = ""
    if !instance
      state = VM_STATE[:deleted]
    else
      state = case instance['data'][0]['state'].upcase
      when "RUNNING", "STARTING" 
        VM_STATE[:active]
      when "TERMINATED", "STOPPED", "REBOOTING" 
        VM_STATE[:paused]
      else
        VM_STATE[:deleted]
      end
    end
    info << "#{POLL_ATTRIBUTE[:state]}=#{state} "


    POLL_ATTRS.map { |key|
      value = instance['data'][0]["#{key}"]
      if !value.nil? && !value.empty?
        if value.kind_of?(Hash)
          value_str = value.inspect
        else
          value_str = value
        end

        # TODO: In the case of _PUBLICADDRESSES or _PRIVATEADDRESSES keys,
        # handle the case in which multiple addresses are passed.
        # Use comma-separated list (e.g., interface to E-CEO portal)
        info << "LIBCLOUD_#{key.to_s.upcase}=#{value_str.join(",")} "

      end
    }

        log("#{LOG_LOCATION}/#{vm_id}.log","info","poll returning:\n #{info.to_s}")
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
