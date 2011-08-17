#
# Copyright (c) 2011 Dell Inc.
#

# Common BIOS methods which get executed on both the install and update
# phase.


node["crowbar"] = {} if node["crowbar"].nil?
node["crowbar"]["status"] = {} if node["crowbar"]["status"].nil?
node["crowbar"]["status"]["bios"] = []

@@debug = node[:bios][:debug]

centos = ubuntu = false
platform = node[:platform]
case platform
  when "centos", "redhat"
  centos = true
  when "ubuntu"
  ubuntu = true
end

log("BIOS: running on OS:[#{platform}] on #{node[:dmi][:system][:product_name]} hardware") { level :info} 


## enforce platfrom limitations
@@bios_setup_enable = node[:bios][:bios_setup_enable] & centos
@@bios_update_enable = node[:bios][:bios_update_enable] & centos

node["crowbar"]["status"]["bios"] << "Bios Barclamp using centos:#{centos} ubuntu:#{ubuntu}"
node["crowbar"]["status"]["bios"] << "Bios Barclamp using setup_enabled = #{@@bios_setup_enable}"
node["crowbar"]["status"]["bios"] << "Bios Barclamp using update_enabled = #{@@bios_update_enable}"
node.save

