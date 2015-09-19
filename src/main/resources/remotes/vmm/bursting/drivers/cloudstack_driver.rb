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

  # Public provider commands costants
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
      :args => {
        "ID" => {
          :opt => 'id'
        },
      },
    },
    :delete => {
      :cmd => :destroy,
      :subcmd => :virtualmachine,
      :args => {
        "ID" => {
          :opt => 'id'
        },
        "EXPUNGE" => {
          :opt => 'expunge'
        },
      },
    },
    :reboot => {
      :cmd => :reboot,
      :subcmd => :virtualmachine,
      :args => {
        "ID" => {
          :opt => 'id'
        },
      },
    },
    :save => {
      :cmd => :stop,
      :subcmd => :virtualmachine,
      :args => {
        "ID" => {
          :opt => 'id'
        },
      },
    },
    :resume => {
      :cmd => :start,
      :subcmd => :virtualmachine,
      :args => {
        "ID" => {
          :opt => 'id'
        },
      },
    },
    :job => {
      :cmd => :query,
      :subcmd => :asyncjobresult,
      :args => {
        "ID" => {
          :opt => 'jobid'
        },
      },
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
    
    @context_path.concat("/#{@host['provider']}/")
    
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
    
    log("#{LOG_LOCATION}/#{vm_id}.log","deploy","Command:#{@cli_cmd} #{@auth} #{cmd} #{subcmd} #{args}")
    
    begin
      # Synchronous call
      # This implies asyncblock = true in the cloudmonkey configuration
      # It is needed to avoid the RUNNING state before the instance is
      # actualy Running.
      rc, info = do_command("#{@cli_cmd} #{@auth} #{cmd} #{subcmd} #{args}")
      
      raise "Error creating the instance" if !rc
    rescue => e
      STDERR.puts e.message
      exit(-1)
    end

    log("#{LOG_LOCATION}/#{vm_id}.log","deploy","API Info: #{info}")
    
    deploy_id = JsonPath.on(info, "$..virtualmachine.id")[0]
    
    log("#{LOG_LOCATION}/#{vm_id}.log","deploy","Deploy ID: #{deploy_id}")
    
    return deploy_id
  end
  
  def get_instance(deploy_id)
    
    cmd    = self.class::PUBLIC_CMD[:get][:cmd]
    subcmd = self.class::PUBLIC_CMD[:get][:subcmd]
    args   = "#{self.class::PUBLIC_CMD[:get][:args]["ID"][:opt]}=#{deploy_id}"
    
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
  
  def destroy_instance(deploy_id)
    
    cmd    = self.class::PUBLIC_CMD[:delete][:cmd]
    subcmd = self.class::PUBLIC_CMD[:delete][:subcmd]
    args   = "#{self.class::PUBLIC_CMD[:delete][:args]["ID"][:opt]}=#{deploy_id}"
    
    args.concat(" ")
    args.concat("#{self.class::PUBLIC_CMD[:delete][:args]["EXPUNGE"][:opt]}=True")
    
    vm = get_instance(deploy_id)
  
    begin
      rc, info = do_command("#{@cli_cmd} #{@auth} #{cmd} #{subcmd} #{args}")
    end while !rc 
    
    # The context_id is one of the privateaddresses.
    # The safest solution is to check and remove all the privateaddresses 
    # associated to the vm.    
    key = DRV_POLL_ATTRS.invert[POLL_ATTRS[:privateaddresses]]
    privateaddresses = JsonPath.on(vm, "$..#{key}")
    
    privateaddresses.each { |privateaddress|
      remove_context(privateaddress.gsub(".", "-"))
    }

    return info
  end
  
  def reboot_instance(deploy_id)
    
    cmd    = self.class::PUBLIC_CMD[:reboot][:cmd]
    subcmd = self.class::PUBLIC_CMD[:reboot][:subcmd]
    args   = "#{self.class::PUBLIC_CMD[:reboot][:args]["ID"][:opt]}=#{deploy_id}"
  
    begin
      rc, info = do_command("#{@cli_cmd} #{@auth} #{cmd} #{subcmd} #{args}")
    end while !rc 

    return info
  end
  
  def save_instance(deploy_id)
    
    cmd    = self.class::PUBLIC_CMD[:save][:cmd]
    subcmd = self.class::PUBLIC_CMD[:save][:subcmd]
    args   = "#{self.class::PUBLIC_CMD[:save][:args]["ID"][:opt]}=#{deploy_id}"
  
    begin
      rc, info = do_command("#{@cli_cmd} #{@auth} #{cmd} #{subcmd} #{args}")
    end while !rc

    return info
  end
  
  def resume_instance(deploy_id)
    
    cmd    = self.class::PUBLIC_CMD[:resume][:cmd]
    subcmd = self.class::PUBLIC_CMD[:resume][:subcmd]
    args   = "#{self.class::PUBLIC_CMD[:resume][:args]["ID"][:opt]}=#{deploy_id}"
  
    begin
      rc, info = do_command("#{@cli_cmd} #{@auth} #{cmd} #{subcmd} #{args}")
    end while !rc 

    return info
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
        next if vm["state"] != "Running" && vm["state"] != "Starting"
        
        poll_data = parse_poll(vm)
        
        displayname = vm["displayname"]
        id = vm["id"]
        
        one_id = displayname.match(/one-(.*)/)
        
        next if one_id.nil?
        
        deploy_id = id
        
        vms_info << "VM=[\n"
                  vms_info << "  ID=#{one_id[1] || -1},\n"
                  vms_info << "  DEPLOY_ID=#{deploy_id},\n"
                  vms_info << "  POLL=\"#{poll_data}\" ]\n"
                  
        
        # Create the context for the VM 
        privateaddresses_attr = DRV_POLL_ATTRS.invert[POLL_ATTRS[:privateaddresses]]
        privateaddresses = JsonPath.on(vm, "$..#{privateaddresses_attr}")
        
        if privateaddresses.length > 0
          # The context_id is one of the privateaddresses.
          # The safest solution is to create a context for all the
          # privateaddresses associated to the vm.
          privateaddresses.each { |privateaddress|
            create_context(context_xml, privateaddress.gsub(".", "-"))
          }
        end 
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
  
  def log(file,action,text)

    time = Time.now.strftime("%Y/%m/%d %H:%M")
    open(file, 'a') { |f|
      f.puts "[#{time}] [#{action}] #{text}"
    }
    
  end

end
