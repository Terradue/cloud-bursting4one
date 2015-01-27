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

  #TODO use '/usr/bin/jclouds-cli' as PATH
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

    @hostname = host
    
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

  def monitor_all_vms(host_id)

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
    host_info << "HOSTNAME=\"#{@hostname}\"\n"

    vms_info = "VM_POLL=YES\n"

    # In the case of the jclouds driver is not possible to assign a name
    # or a TAG to the VM, as in the case of EC2 client. In this way a VM
    # started from the OpenNebula cannot be discriminated from one started
    # from another client. The solution here is to perform a polling call for
    # each VM.
    # The OpenNebula's Ruby API is used To get all the instances associated
    # with the 'host' specified.

    host = Host.new(Host.build_xml(host_id),::OpenNebula::Client.new())
    xml_host = Document.new(host.monitoring_xml)

    usedcpu    = 0
    usedmemory = 0

    XPath.each(xml_host, "//HOST[last()]/VMS/ID") { |e1|
      id = e1.text
      # get VM deploy_id and instance_type from opennebula
      # deploy_id =
      # instance_type =
      vm = VirtualMachine.new(VirtualMachine.build_xml(id),::OpenNebula::Client.new())

      xml_vm = Document.new(vm.monitoring_xml)
      
      XPath.each(xml_vm, "//VM[last()]/DEPLOY_ID") { |e2| deploy_id = e2.text }
      
      instance = get_instance(deploy_id)
      poll_data = parse_poll(instance)
 
      vms_info << "VM=[\n"
                vms_info << "  ID=#{id || -1},\n"
                vms_info << "  DEPLOY_ID=#{deploy_id},\n"
                vms_info << "  POLL=\"#{poll_data}\" ]\n"
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
