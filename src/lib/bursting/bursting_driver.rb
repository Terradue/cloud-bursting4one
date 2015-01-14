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

ONE_LOCATION = ENV["ONE_LOCATION"] if !defined?(ONE_LOCATION)

if !ONE_LOCATION
    RUBY_LIB_LOCATION = "/usr/lib/one/ruby" if !defined?(RUBY_LIB_LOCATION)
    ETC_LOCATION      = "/etc/one/" if !defined?(ETC_LOCATION)
else
    RUBY_LIB_LOCATION = ONE_LOCATION + "/lib/ruby" if !defined?(RUBY_LIB_LOCATION)
    ETC_LOCATION      = ONE_LOCATION + "/etc/" if !defined?(ETC_LOCATION)
end

T2_RUBY_LIB_LOCATION = "/usr/lib/t2/ruby"

require 'yaml'
require 'rubygems'
require 'uri'

$: << RUBY_LIB_LOCATION
$: << T2_RUBY_LIB_LOCATION

require 'CommandManager'
require 'scripts_common'
require 'rexml/document'
require 'VirtualMachineDriver'

# The parent class for the Bursting driver
class BurstingDriver

  ACTION          = VirtualMachineDriver::ACTION
  POLL_ATTRIBUTE  = VirtualMachineDriver::POLL_ATTRIBUTE
  VM_STATE        = VirtualMachineDriver::VM_STATE
  
  DRIVER_CONF = ""

  def self.create(type,host)
    case type
    when :jclouds
      JcloudsDriver.new(host)
    else
      raise "Bad bursting type: #{type}"
    end
  end    

  # Constructor
  def initialize(host)
    @host = host
    load_configuration
  end

  # DEPLOY action
  def deploy(id, host, xml_text); end

  # Shutdown an instance
  def shutdown(deploy_id)
    action(deploy_id, :shutdown)
  end

    # Reboot an instance
    def reboot(deploy_id)
        action(deploy_id, :reboot)
    end

    # Cancel an instance
    def cancel(deploy_id)
        action(deploy_id, :delete)
    end

    # Stop an instance
    def save(deploy_id)
        action(deploy_id, :shutdown)
    end

    # Cancel an  instance
    def restore(deploy_id)
        action(deploy_id, :start)
    end

    # Get info for an instance
    def poll(id, deploy_id)
        i = get_instance(deploy_id)
        puts parse_poll(i)
    end

    # Get the info of all instances. An instance must have
    # a name compliant with the "one-#####_csn" format, where ##### are intengers
    def monitor_all_vms
    end

private

    # Get the associated capacity of the instance_type as cpu (in 100 percent
    # e.g. 800 for 8 cores) and memory (in KB)
    def instance_type_capacity(name)
        return 0, 0 if @instance_types[name].nil?
        return @instance_types[name]['cpu'].to_i * 100 ,
               @instance_types[name]['memory'].to_i * 1024 * 1024
    end

    # Get the Bursting section of the template. If more than one Bursting section
    # the LOCATION element is used and matched with the host
    def get_deployment_info(host, xml_text)
    end

    # Retrive the vm information from the instance
    def parse_poll(instance)
    end

    def format_endpoints(endpoints)
    end

    def create_params(id,csn,info)
    end

    def create_options(id,csn,info)
    end

    # Execute a command
    # +deploy_id+: String, VM id 
    # +action+: Symbol, one of the keys of the hash constant (i.e :run)
    def action(deploy_id, action)
    end

    # Returns the value of the xml specified by the name or the default
    # one if it does not exist
    # +xml+: REXML Document, containing Public Cloud information
    # +name+: String, xpath expression to retrieve the value
    # +block+: Block, block to be applied to the value before returning it
    def value(xml, name, &block)
        value = value_from_xml(xml, name) || @defaults[name]
        if block_given? && value
            block.call(value)
        else
            value
        end
    end

    def value_from_xml(xml, name)
        if xml
            element = xml.elements[name]
            element.text.strip if element && element.text
        end
    end

    # Load the default values that will be used to create a new instance, if
    #   not provided in the template.
    def load_default_template_values
    end

  def load_configuration
    @public_cloud_conf  = YAML::load(File.read(self.class::DRIVER_CONF))
  end

    def in_silence
    end    

    # Retrive the instance from the Public Provider. If OpenNebula asks for it, then the 
    # vm_name must comply with the notation name_csn
    def get_instance(vm_name)
    end
end

