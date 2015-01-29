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

require 'yaml'
require 'rubygems'
require 'uri'
require 'json'

$: << RUBY_LIB_LOCATION

require 'CommandManager'
require 'scripts_common'
require 'rexml/document'
require 'VirtualMachineDriver'
require 'opennebula'

include OpenNebula

# The parent class for the Bursting driver
class BurstingDriver

  ACTION          = VirtualMachineDriver::ACTION
  POLL_ATTRIBUTE  = VirtualMachineDriver::POLL_ATTRIBUTE
  VM_STATE        = VirtualMachineDriver::VM_STATE
  
  # Driver's configuration files
  DRIVER_CONF    = ""
  DRIVER_DEFAULT = ""
  
  # Public provider tag in the VM template
  PUBLIC_TAG = "PUBLIC_CLOUD"

  # Public provider commands costants
  PUBLIC_CMD = nil

  # Public provider attributes that will be retrieved in a polling action
  POLL_ATTRS = nil

  DRIVERS = {
    :jclouds => 'jclouds'
  }

  def self.create(type,host)
    case type
    when DRIVERS[:jclouds]
      JcloudsDriver.new(host)
    else
      raise "Bad bursting driver type: #{type}"
    end
  end

  # Determining the bursting 'type', currently with a XML-RPC call
  # (it would be preferred through the ARGV arguments)
  # +vm_id+: String, representing the ID of the VM
  def self.get_type(vm_id)
    type = ""
    client = Client.new()

    xml = client.call("vm.info", vm_id.to_i)

    vm_xml = REXML::Document.new(xml) if xml
    
    REXML::XPath.each(vm_xml, "//PUBLIC_CLOUD/TYPE") { |e| type = e.text  }

    raise "Provider type is not defined/determined" if type.empty?
    
    return type 
  end  

  # Constructor
  # +host+: String, representing the name of the host
  def initialize(host)
    @host = host
    load_configuration
  end

  # Deploy an instance
  # +vm_id+: String, representing the ID of the VM
  # +host+: String, representing the name of the host
  # +xml_text+: String, containing VM information in XML format
  def deploy(vm_id, host, xml_text)
    load_default_template_values

    info = get_deployment_info(host, xml_text)

    # TODO Make an abstraction of the validation phase
    if !value(info, 'IMAGEID')
      STDERR.puts("Cannot find IMAGEID in deployment file")
      exit(-1)
    end

    opts = generate_options(:run, info, {})

    begin
      instance_id = create_instance(opts)
    rescue => e
      STDERR.puts(e.message)
      exit(-1)
    end

    puts instance_id
  end

  # Shutdown an instance
  # +deploy_id+: String, representing the VM deploy ID
  def shutdown(deploy_id)
    destroy_instance(deploy_id)
  end

  # Reboot an instance
  # +deploy_id+: String, representing the VM deploy ID
  def reboot(deploy_id)
    action(deploy_id, :reboot)
  end

  # Cancel an instance
  # +deploy_id+: String, representing the VM deploy ID
  def cancel(deploy_id)
    destroy_instance(deploy_id)
  end

  # Stop an instance
  # +deploy_id+: String, representing the VM deploy ID
  def save(deploy_id)
    action(deploy_id, :shutdown)
  end

  # Cancel an  instance
  # +deploy_id+: String, representing the VM deploy ID
  def restore(deploy_id)
    action(deploy_id, :start)
  end

  # Get info for an instance
  # +vm_id+: String, representing the VM ID
  # +deploy_id+: String, representing the VM deploy ID
  def poll(vm_id, deploy_id)
    instance = get_instance(deploy_id)
    puts parse_poll(instance)
  end

  # Get the info of all instances.
  # +host_id+: String, representing the ID of the host
  def monitor_all_vms(host_id); end

private

  # Get the associated capacity of the instance_type as cpu (in 100 percent
  # e.g. 800 for 8 cores) and memory (in KB)
  # +name+: String, the instance type name
  def instance_type_capacity(name)
    return 0, 0 if @instance_types[name].nil?
    return @instance_types[name]['cpu'].to_i * 100 ,
           @instance_types[name]['memory'].to_i * 1024 * 1024
  end

  # Get the Bursting section of the template. If more than one Bursting section
  # the LOCATION element is used and matched with the host
  # +host+: String, representing the name of the host
  # +xml_text+: String, containing VM information in XML format
  def get_deployment_info(host, xml_text)
    xml = REXML::Document.new xml_text

    public_cloud = nil

    all_elements = xml.root.get_elements("//USER_TEMPLATE/#{self.class::PUBLIC_TAG}")

    # First, let's see if we have a site that matches the desired host name
    all_elements.each { |element|
      cloud=element.elements["HOST"]
      if cloud and cloud.text.upcase == host.upcase
        public_cloud = element
      end
    }

    if !public_cloud
      # If we don't find the self.class::PUBLIC_TAG site, and ONE just
      # knows about one self.class::PUBLIC_TAG site, let's use that
      if all_elements.size == 1
        public_cloud = all_elements[0]
      else
        STDERR.puts("Cannot find #{self.class::PUBLIC_TAG} element in deployment file or no" \
        "#{self.class::PUBLIC_TAG} site matching in the template.")
        exit(-1)
      end
    end

    public_cloud
  end 

  # Retrieve the context information 
  # +xml_text+: REXML Document, containing VM information
  def get_context_info(xml_text)
    xml = REXML::Document.new xml_text

    context = xml.root.get_elements("//CONTEXT")
  end
  
  # Create the context files in the local filesystem
  # +xml_text+: REXML Document, containing CONTEXT information
  # +vm_id+: String, context ID (typically a representation of the VM's IP)
  # +context_path+: String, path of the context on the local filesysem
  def create_context(xml_text, context_id, context_path)
    context_dir = context_path + '/' + context_id
    
    # Creating context directory      
    FileUtils.mkdir_p context_dir
    
    tar_filename = 'context.tgz'
        
    context_xml = get_context_info(xml_text)

    if !context_xml.nil?
      file = File.new("#{context_dir}/context.sh", 'w')

      file.write("# Context variables generated by Opennebula's Cloud Bursting driver\n")

      context_xml[0].elements.each { |e|
        file.write("#{e.name}='#{e.text}'\n")

        # do the copy
        if e.name == "FILES"
          e.text.split(' ').each { |path|
            begin
              rc, info = do_command("/bin/cp #{path} #{context_dir}")

              raise "Error copying context file #{path}" if !rc
            rescue => e
              STDERR.puts e.message
              exit(-1)
            end 
          }
        end
      }

      file.close
    end 
        
    # Creating the tarball
    begin                
      rc, info = do_command("cd #{context_dir}; tar -cvzf #{tar_filename} * > /dev/null 2>&1")
     
      raise "Error creating context tarball #{tar_filename}" if !rc
    rescue => e
      STDERR.puts e.message
      exit(-1)
    end
  end
  
  # Remove the context files from the local filesystem
  # +vm_id+: String, context ID (typically a representation of the VM's IP)
  # +context_path+: String, path of the context on the local filesysem
  def remove_context(context_id, context_path)
    context_dir = context_path + '/' + context_id
    
    FileUtils.rm_rf context_dir
  end

  # Generate the options for the given command from the xml provided in the
  #   template. The available options for each command are defined in the
  #   PUBLIC_CLOUD constant
  # +action+: Symbol, one of the keys of the hash constant (i.e :run)
  # +xml+: REXML Document, containing Public Cloud information
  # +extra_params+: Array, containing extra parameters to add
  def generate_options(action, xml, extra_params={})
    opts = extra_params || {}

    if self.class::PUBLIC_CMD[action][:args]
      self.class::PUBLIC_CMD[action][:args].each {|k,v|
        str = value(xml, k, &v[:proc])
        if str
          tmp = opts
          last_key = nil
          v[:opt].split('/').each { |k|
            tmp = tmp[last_key] if last_key
            tmp[k] = {}
            last_key = k
          }
          tmp[last_key] = str
        end
      }
    end

    opts
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

  # Return the value from the given xml and element name
  # +xml+: REXML Document
  # +name+: String, element name
  def value_from_xml(xml, name)
    if xml
      element = xml.elements[name]
      element.text.strip if element && element.text
    end
  end
  
  # Load the provider configuration values
  def load_configuration
    @public_cloud_conf  = YAML::load(File.read(self.class::DRIVER_CONF))
  end

  # Load the default values that will be used to create a new instance, if
  # not provided in the template.
  def load_default_template_values
    @defaults = Hash.new

    if File.exists?(DRIVER_DEFAULT)
      fd  = File.new(DRIVER_DEFAULT)
      xml = REXML::Document.new fd
      fd.close()

      return if !xml || !xml.root

      public_cloud = xml.root.elements[self.class::PUBLIC_TAG]

      return if !public_cloud

      PUBLIC_CMD.each {|action, hash|
        if hash[:args]
          hash[:args].each { |key, value|
            @defaults[key] = value_from_xml(public_cloud, key)
          }
        end
      }
    end
  end
    
  # Create the instance on the Public Provider
  def create_instance(opts)
    raise "You should implement this method."
  end

  # Retrieve the instance information from the Public Provider
  # +deploy_id+: String, representing the VM deploy ID
  def get_instance(deploy_id)
    raise "You should implement this method."
  end
  
  # Destroy the instance on the Public Provider
  # +deploy_id+: String, VM deploy ID
  def destroy_instance(deploy_id)
    raise "You should implement this method."
  end
  
  # Parse the VM information from the instance info
  # +instance_info+: String, instance information
  def parse_poll(instance_info)
    raise "You should implement this method."
  end
  
end
