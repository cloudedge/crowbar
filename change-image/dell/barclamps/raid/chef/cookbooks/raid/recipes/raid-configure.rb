#
# Copyright (c) 2011 Dell Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#


include_recipe "utils"

raid_enable = node[:raid][:enable] & @@centos
log("BEGIN raid-install enabled=#{raid_enable}") {level :info} 

config_name = node[:crowbar][:hardware][:raid_set] rescue config_name = "JBODOnly"
config_name ="raid-#{config_name}"
config_bag = data_bag("crowbar-data")
config = data_bag_item("crowbar-data",config_name) if config_bag.include?(config_name)
log("Using config: #{config_name}")
begin 
## push the MegaCLI packages, and insall them

["Lib_Utils-1.00-09.noarch.rpm", "MegaCli-8.00.48-1.i386.rpm"].each { |pkg| 
  cookbook_file "/root/#{pgk}" do
    source pkg    
  end
  
  rpm_package pkg do
    action :install
    source pkg
  end
}  
  
  raid_raid_config "lsi_ircu" do
    config config["config"]
    debug_flag node[:raid][:debug]  
    action [:apply, :report]
  end
end if raid_enable and !config.nil? and !config.empty?
log("END raid-install") {level :info} 
