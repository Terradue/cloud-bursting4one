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
require 'occi-api'

include REXML

class OcciDriver < BurstingDriver

  DRIVER_CONF    = "#{ETC_LOCATION}/occi_driver.conf"
  DRIVER_DEFAULT = "#{ETC_LOCATION}/occi_driver.default"

  # Child driver specific attributes
  DRV_POLL_ATTRS = {
    :privateaddress => POLL_ATTRS[:privateaddresses],
    :publicaddress  => POLL_ATTRS[:publicaddresses]
  }
  
  # Public provider commands costants
  PUBLIC_CMD = {
    :run => {
      :cmd => :create,
      :args => {
        "OS_TPL" => {
          :opt => 'os_tpl'
        },
        "RESOURCE_TPL" => {
          :opt => 'resource_tpl'
        },
      },
    }
  }

  def initialize(host)
    
    super(host)

    @context_path   = @public_cloud_conf['context_path']
    @ca_path        = @public_cloud_conf['ca_path']
    @instance_types = @public_cloud_conf['instance_types']
    
    @hostname = host
    
    hosts = @public_cloud_conf['hosts']
    @host = hosts[host] || hosts["default"]
    
    @endpoint        = @host['endpoint']
    @x509_user_proxy = @host['x509_user_proxy']
    @voms            = @host['voms']
    @type            = @host['type']
    @context_path.concat("/#{@host['provider']}/")
    
  end

  def create_instance(vm_id, opts, context_xml)
    
    # TODO: Manage the user proxy based on the actual user requesting it
    user_cert = @x509_user_proxy
    
    occi    = get_occi_client user_cert
    compute = occi.get_resource "compute"
    storage = value_from_xml(context_xml[0],"STORAGE_SIZE")

    ## attach chosen resources to the compute resource
    opts.each {|k,v|
      compute.mixins << v
    }
    
    log("#{LOG_LOCATION}/#{vm_id}.log","create","Start deploying one-#{vm_id}")
    
    ## set the title
    compute.title = "one-#{vm_id}"
    
    ## create the compute resource and get its location
    deploy_id = occi.create compute
    
    log("#{LOG_LOCATION}/#{vm_id}.log","create","Compute #{deploy_id} created")
    
    if storage
      
      log("#{LOG_LOCATION}/#{vm_id}.log","create","Creating additional storage of #{storage} GB")
      
      storage       = occi.get_resource "storage"
      storage.size  = storage #In GB
      storage.title = "one-#{vm_id} additional disk"
      
      storage_id = occi.create storage
      
      log("#{LOG_LOCATION}/#{vm_id}.log","create","Additional storage created with id: #{storage_id}")
    end
    
    ## get the compute resource data
    compute_data = occi.describe deploy_id
    
    ## wait until the resource is "active"
    while compute_data.first.attributes.occi.compute.state == "inactive"
      sleep 1
      compute_data = occi.describe deploy_id
    end
    
    ## wait until the resource provides the IP
    while compute_data.first.links.first.attributes.occi.networkinterface.address == ""
      sleep 1
      compute_data = occi.describe deploy_id
    end
    
    log("#{LOG_LOCATION}/#{vm_id}.log","create","Compute #{deploy_id} ready")
    
    # This step is performed here because both 'compute' and 'storage' resources
    # shall be ready before linking them
    if storage
      
      log("#{LOG_LOCATION}/#{vm_id}.log","create","linking storage #{storage_id}")
      
      link        = Occi::Core::Link.new("http://schemas.ogf.org/occi/infrastructure#storagelink")
      link.source = deploy_id
      link.target = storage_id

      occi.create link
      
      log("#{LOG_LOCATION}/#{vm_id}.log","create","storage linked")
    end
        
    # The context_id is one of the IP addresses.
    # The safest solution is to create a context for all the
    # addresses associated to the vm.
    compute_data.first.links.each { |link|
      address = link.attributes.occi.networkinterface.address
      log("#{LOG_LOCATION}/#{vm_id}.log","create","Preparing context for #{address}")
      create_context(context_xml, address.gsub(".", "-"))
    }
    
    log("#{LOG_LOCATION}/#{vm_id}.log","create","Deploy completed")
    
    return deploy_id
  end
  
  def destroy_instance(deploy_id)
  
    occi = get_occi_client

    begin
      compute_data = occi.describe deploy_id
      
      raise "Instance #{deploy_id} does not exist" if !compute_data
    rescue => e
      STDERR.puts e.message
      exit(-1)
    end
    
    vm_id = compute_data.first.attributes.occi.core.title.match(/one-(.*)/)[1]
    
    log("#{LOG_LOCATION}/#{vm_id}.log","destroy","Start")
    
    begin
      result = occi.delete deploy_id
      
      raise "Instance #{deploy_id} does not exist" if !result
    rescue => e
      STDERR.puts e.message
      exit(-1)
    end
    
    # The context_id is one of the privateaddresses.
    # The safest solution is to check and remove all the addresses 
    # associated to the vm.
    
    compute_data.first.links.each { |link|
      address = link.attributes.occi.networkinterface.address
      remove_context(address.gsub(".", "-"))
    }

    log("#{LOG_LOCATION}/#{vm_id}.log","destroy","End")
    
    return deploy_id
  end
  
  def reboot_instance(deploy_id)
    
    occi = get_occi_client

    begin
      
      result = occi.trigger(deploy_id,get_actioninstance("restart"))
      
      raise "Instance #{deploy_id} does not exist" if !result
    rescue => e
      STDERR.puts e.message
      exit(-1)
    end 

    return result
  end
  
  def save_instance(deploy_id)
    
    occi = get_occi_client

    begin
      result = occi.trigger(deploy_id,get_actioninstance("suspend"))
      
      raise "Instance #{deploy_id} does not exist" if !result
    rescue => e
      STDERR.puts e.message
      exit(-1)
    end 

    return result
  end
  
  def resume_instance(deploy_id)
    
    occi = get_occi_client

    begin
      result = occi.trigger(deploy_id,get_actioninstance("start"))
      
      raise "Instance #{deploy_id} does not exist" if !result
    rescue => e
      STDERR.puts e.message
      exit(-1)
    end 

    return result
  end

  def monitor_all_vms(host_id)
    
    occi = get_occi_client
        
    totalmemory = 0
    totalcpu = 0
    @host['capacity'].each { |name, size|
      cpu, mem = instance_type_capacity(name)

      totalmemory += mem * size.to_i
      totalcpu    += cpu * size.to_i
    }

    host_info =  "HYPERVISOR=occi\n"
    host_info << "PUBLIC_CLOUD=YES\n"
    host_info << "PRIORITY=-1\n"
    host_info << "TOTALMEMORY=#{totalmemory.round}\n"
    host_info << "TOTALCPU=#{totalcpu}\n"
    host_info << "CPUSPEED=1000\n"
    host_info << "HOSTNAME=\"#{@hostname}\"\n"

    vms_info = "VM_POLL=YES\n"

    usedcpu    = 0
    usedmemory = 0
    
    begin
      compute_data = occi.list "compute"
      
      raise "Error during the listing of the occi compute resources" if !compute_data
    rescue => e
      STDERR.puts e.message
      exit(-1)
    end
    
    if !compute_data.empty?
    
      # For each instance 'virtualmachine'
      compute_data.each { |vm|

        begin
          vm_info = occi.describe "#{vm}"
        rescue => e
          STDERR.puts e.message
          next
        end

        next if vm_info.first.attributes.occi.compute.state != "active"

        poll_data = parse_poll(vm_info)

        displayname = vm_info.first.attributes.occi.core.title
        id = "#{@endpoint}/compute/#{vm_info.first.attributes.occi.core.id}"
        
        one_id = displayname.match(/one-(.*)/)
        
        next if one_id.nil?
        
        deploy_id = id
        
        vms_info << "VM=[\n"
                  vms_info << "  ID=#{one_id[1] || -1},\n"
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
        state = case vm.first.attributes.occi.compute.state
        when "active"
          VM_STATE[:active]
        # TODO Check the actual states
        when "suspended", "stopping", 
          VM_STATE[:paused]
        else
          VM_STATE[:deleted]
        end
      end
    
      info << "#{POLL_ATTRIBUTE[:state]}=#{state} "
      
      # TODO Understand the expected network types - just network/fixed with INFN Bari
      address = vm.first.links.first.attributes.occi.networkinterface.address
      
      if address
        info << "OCCI_#{ POLL_ATTRS[:publicaddresses].upcase}=#{URI::encode(address)} "
      end 
          
      info
    rescue => e
      # Unkown state if exception occurs retrieving information from
      # an instance
      STDERR.puts e.message
      "#{POLL_ATTRIBUTE[:state]}=#{VM_STATE[:unknown]} "
    end
  end
 
private

  def get_occi_client(user_cert=@x509_user_proxy)

    begin
      ## get an OCCI::Api::Client::ClientHttp instance
      occi = Occi::Api::Client::ClientHttp.new({
        :endpoint => @endpoint,
        :auth => {
          :type               => @type,
          :user_cert          => user_cert,
          :ca_path            => @ca_path,
          :voms               => @voms
        },
        :log => {
          :out   => STDERR,
          :level => Occi::Api::Log::INFO
        }
      })
    
      occi
    rescue => e
      STDERR.puts e.message
      exit(-1)
    end
    
  end
  
  def get_actioninstance(term)
    
    action = Occi::Core::Action.new("http://schemas.ogf.org/occi/infrastructure/compute/action",term)
    return Occi::Core::ActionInstance.new(action)
    
  end
  
  def do_command(cmd)
    
    rc = LocalCommand.run(cmd)

    if rc.code == 0
      return [true, rc.stdout]
    else
      STDERR.puts("Error executing: #{cmd} err: #{rc.stderr} out: #{rc.stdout}")
      return [false, rc.code]
    end
  end
  
  def log(file,action,text)

    time = Time.now.strftime("%Y/%m/%d %H:%M")
    open(file, 'a') { |f|
      f.puts "[#{time}] [#{action}] #{text}"
    }
    
  end

end
