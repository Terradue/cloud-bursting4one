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
          :opt => 'hardwareid'
        },
        "IMAGEID" => {
          :opt => 'imageid'
        },
        "LOCATIONID" => {
          :opt => 'locationid'
        },
        "GROUP" => {
          :opt => 'group'
        },
      },
    },
    :get => {
      :cmd => :get
      :args => {
        "NODEID" => {
          :opt => 'nodeid'
        },
    },
    :shutdown => {
      :cmd => :destroy
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
    :private_ip_address,
    :ip_address
  ]

  JCLOUDS_CMD = "java -jar /usr/lib/jclouds-cli/jclouds-cli.jar"

  def initialize(host)
    super(host)

    @instance_types = @public_cloud_conf['instance_types']
    
    regions = @public_cloud_conf['regions']
    @region = regions[host] || regions["default"]
  end

  def create_instance(opts)
    provider   = "aws-ec2"
    identity   = @region['access_key_id']
    credential = @region['secret_access_key']
    group      = opts['group']
    command    = "listimages"

    rc, info = do_command("#{JCLOUDS_CMD} #{provider} #{identity} #{credential} #{group} #{command}")

    # TODO Placeholder
    puts "instanceid"
  end

  # Retrive the instance from EC2
  def get_instance(id)
    begin
      rc, info = do_command("#{JCLOUDS_CMD} #{provider} #{identity} #{credential} #{group} #{command} #{id}")
      if rc == true
        return info
      else
        raise "Instance #{id} does not exist"
      end
    rescue => e
      STDERR.puts e.message
        exit(-1)
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
