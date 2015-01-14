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

require 'bursting/bursting_driver'

class JcloudsDriver < BurstingDriver

  DRIVER_CONF = "#{ETC_LOCATION}/jclouds_driver.conf"

  def initialize(host)
    super(host)

    @instance_types = @public_cloud_conf['instance_types']

    regions = @public_cloud_conf['regions']
    @region = regions[host] || regions["default"]
  end

  def deploy(id,host,xml_text)
    super()
  end
end
