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
    :ipaddress     => POLL_ATTRS[:privateaddresses],
    :publicaddress => POLL_ATTRS[:publicaddresses]
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
    user_cert = "/tmp/x509_pusp_catania"
    
    occi    = get_occi_client user_cert
    compute = occi.get_resource "compute"
    
    # TODO Check the actual method parameters
    os = occi.get_mixin(OS_TEMPLATE, "os_tpl")
    size = occi.get_mixin('medium', "resource_tpl")

    ## attach chosen resources to the compute resource
    compute.mixins << os << size
    
    ## set the title
    compute.title = "one-#{vm_id}"
    
    ## create the compute resource and get its location
    deploy_id = occi.create compute
    
    ## get the compute resource data
    compute_data = occi.describe deploy_id
    
    ## wait until the resource is "active"
    while compute_data[0].resources.first.attributes.occi.compute.state == "inactive"
      sleep 1
      compute_data = occi.describe deploy_id
    end
    
    # TODO Check the actual attributes
    ## wait until the resource provides the internal IP
    while compute_data[0].resources.first.attributes.occi.compute.ip != ""
      sleep 1
      compute_data = occi.describe deploy_id
    end
    
    # The context_id is one of the privateaddresses.
    # The safest solution is to create a context for all the
    # addresses associated to the vm.
    privateaddresses.each { |privateaddress|
      create_context(context_xml, privateaddress.gsub(".", "-"))
    }
    
    return deploy_id
  end
  
  def get_instance(deploy_id)
    
    occi = get_occi_client
    
    begin
      compute_data = occi.describe deploy_id
      
      raise "Instance #{deploy_id} does not exist" if !rc
    rescue => e
      STDERR.puts e.message
      exit(-1)
    end
    
    # TODO Check the actual object to return
    return compute_data[0]
  end
  
  def destroy_instance(deploy_id)
  
    occi = get_occi_client

    begin
      compute_data = occi.describe deploy_id
      
      raise "Instance #{deploy_id} does not exist" if !rc
    rescue => e
      STDERR.puts e.message
      exit(-1)
    end
    
    vm_id = compute_data[0].resources.first.attributes.occi.compute.title.match(/one-(.*)/)[1]
    
    log("#{LOG_LOCATION}/#{vm_id}.log","destroy","Start")
    
    begin
      compute_data = occi.delete(deploy_id)
      
      raise "Instance #{deploy_id} does not exist" if !rc
    rescue => e
      STDERR.puts e.message
      exit(-1)
    end
    
    # The context_id is one of the privateaddresses.
    # The safest solution is to check and remove all the privateaddresses 
    # associated to the vm.    
    key = DRV_POLL_ATTRS.invert[POLL_ATTRS[:privateaddresses]]
    # TODO Check the exact attribute
    privateaddresses = compute_data[0].resources.first.attributes.occi.compute.ip
    
    privateaddresses.each { |privateaddress|
      remove_context(privateaddress.gsub(".", "-"))
    }

    log("#{LOG_LOCATION}/#{vm_id}.log","destroy","End")
    
    # TODO Check the object to return
    return compute_data[0]
  end
  
  def reboot_instance(deploy_id)
    
    occi = get_occi_client

    begin
      compute_data = occi.restart deploy_id
      
      raise "Instance #{deploy_id} does not exist" if !rc
    rescue => e
      STDERR.puts e.message
      exit(-1)
    end 

    # TODO Check the actual object to return
    return compute_data[0]
  end
  
  def save_instance(deploy_id)
    
    occi = get_occi_client

    begin
      compute_data = occi.suspend deploy_id
      
      raise "Instance #{deploy_id} does not exist" if !rc
    rescue => e
      STDERR.puts e.message
      exit(-1)
    end 

    # TODO Check the actual object to return
    return compute_data[0]
  end
  
  def resume_instance(deploy_id)
    
    occi = get_occi_client

    begin
      compute_data = occi.start deploy_id
      
      raise "Instance #{deploy_id} does not exist" if !rc
    rescue => e
      STDERR.puts e.message
      exit(-1)
    end 

    # TODO Check the actual object to return
    return compute_data[0]
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
    
    begin
      compute_data = occi.describe deploy_id
      
      raise "Instance #{deploy_id} does not exist" if !rc
    rescue => e
      STDERR.puts e.message
      exit(-1)
    end
    
    # TODO Check the compute_data object
    if !compute_data[0]resources.empty?
      compute_data[0].resources
    
      # For each instance 'virtualmachine'
      compute_data[0].resources.each { |vm|
        next if vm.attributes.occi.compute.state != "active"
        
        poll_data = parse_poll(vm)
        
        displayname = vm.attributes.occi.compute.title
        id = vm.attributes.occi.compute.id
        
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
        state = case vm.attributes.occi.compute.state
        when "active"
          VM_STATE[:active]
        # TODO Check the actual states
        when "Suspended", "Stopping", 
          VM_STATE[:paused]
        else
          VM_STATE[:deleted]
        end
      end
    
      info << "#{POLL_ATTRIBUTE[:state]}=#{state} "
      
      # Search for the value(s) corresponding to the DRV_POLL_ATTRS keys
      DRV_POLL_ATTRS.map { |key, value|
        # TODO Check the dynamic method works
        results = vm.attributes.occi.compute.public_send(key)
        if results.length > 0
          results.join(",")
          info << "OCCI_#{value.to_s.upcase}=#{URI::encode(results.join(","))} "
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

  # TODO Choose a location for the default PUSP cert 
  def get_occi_client(user_cert=@x509_user_proxy)

    begin
      ## get an OCCI::Api::Client::ClientHttp instance
      occi = Occi::Api::Client::ClientHttp.new({
        :endpoint => ENDPOINT,
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
  
  def log(file,action,text)

    time = Time.now.strftime("%Y/%m/%d %H:%M")
    open(file, 'a') { |f|
      f.puts "[#{time}] [#{action}] #{text}"
    }
    
  end

end
