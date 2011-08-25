#!/c/Ruby187/bin/ruby
#
# Copyright 2011, Dell
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
# Author: andi abes
#

if __FILE__ == $0
  require 'raid_data'
end


class Crowbar
  class RAID
    class LSI_MegaCli < Crowbar::RAID
      
      ## require modprobe mptsas
      CMD = '/opt/MegaRAID/MegaCli/MegaCli64'
      @@vol_re = /Virtual Drive:\s*(\d+)\s*\(Target Id:\s*(\d+)\)/
      @@disk_re = /PD:\s*(\d+)\s*Information/              
      
      def find_controller
        ## adpCount sets the return code to 0 if no controller is found
        begin          
          run_tool(["-adpCount"])
          return nil
        rescue
          ## we have a controller... return it's ID
        end
        @cntrl_id = 0
      end
      
      ## load curent RAID info - volumes and disk info
      def load_info
        phys_disks = run_tool(["-PDlist"])
        @disks = parse_dev_info(phys_disks)
        vols = run_tool(["-ldpdinfo"])
        @volumes = parse_volumes(vols)
      end   
      
      def create_volume(type, name, disk_ids )
        ## build up the command...     
        text = ""
        cmd = []
        case type.intern
          when :RAID0,:RAID1 
          cmd = ["-CfgLdAdd", type == :RAID0 ? "-r0" : "-r1"]
          cmd << "[ #{disk_ids.join(",")} ]"             
          when :RAID10
          cmd = ["-CfgSpanAdd", "-r10" ]
          disk_cnt = disk_ids.length
          span0 = disk_ids[0..disk_cnt/2-1].join(",")
          span1 = disk_ids[disk_cnt/2.. disk_cnt].join(",")         
          cmd << "-Array0[#{span0}]"
          cmd << "-Array1[#{span1}]"
          
          when :JBOD
          raise "JBOD Is not supported"
        else
          raise "unknown raid level requested: #{type}"
        end
        
        run_tool(cmd)
      rescue
        log("create returned: #{text}", :ERROR)
        raise 
      end
      
      def delete_volume(id)
        text = ""
        run_tool(["-CfgLdDel", "-L#{id}"]) { |f|
          text = f.readlines
        }
      rescue
        log("delete returned: #{text}", :ERROR)
        raise 
      end
      
=begin
  Parse information about available pyhsical devices.
  The method expects to parse the output of:
  MegaCli64 -PDlist -aAll
=end     
      def parse_dev_info(lines)
        devs = []
        begin
          rd = Crowbar::RAID::RaidDisk.new    
          skip_to_find lines,/Enclosure Device ID:/  # find a disk
          break if lines.length ==0          
          rd.enclosure = extract_value lines[0]      
          skip_to_find lines,/Device Id/      
          rd.slot = extract_value lines[0]
          log(" disk: #{rd.enclosure} / #{rd.slot}")
          devs << rd
        end while lines.length > 0
        devs
      end
      
      
      
=begin      
  Break the output into "stanzas"- one for each volume, and 
  pass the buck down to the volume parsing method.     

  The method expects the output of:
  MegaCli64 -ldpdinfo -aAll
=end
      def parse_volumes(lines)    
        vols = []    
        txt = save = ""
        # find first volume
        skip_to_find lines, @@vol_re
        begin
          # find the next one, to "bracket"the volume
          save = lines.shift if lines.length > 0 
          txt = skip_to_find lines, @@vol_re
          next if txt.length ==0  # no more info          
          vols << parse_vol_info([ save ] + txt)
        end while txt.length > 0   
        vols
      end
      
=begin
  Parse info about one volume
=end  
      
      def parse_vol_info(lines)        
        rv = Crowbar::RAID::Volume.new
        skip_to_find lines, @@vol_re
        return if lines.length ==0 and log("no more info") 
        ## MegaCli doesn't give volumes names.. use the target ID as the na
        rv.vol_id, rv.vol_name = @@vol_re.match(lines[0])[1,2]
        log ("volume id: #{rv.vol_id} #{rv.vol_name}")
        skip_to_find lines, /RAID Level/
        raid_level = extract_value lines[0]
        case raid_level
          when /Primary-0, Secondary-0/
          rv.raid_level = :RAID0
          when /Primary-1, Secondary-0/
          rv.raid_level = :RAID1
        end          
        rv.members = parse_dev_info(lines)
        rv
      end    
      
      def run_tool(args, &block)    
        cmd = [CMD, *args]
        cmd << "-a#{@cntrl_id}" unless @cntrl_id.nil?
        cmdline = cmd.join(" ")
        run_command(cmdline, &block)
      end
    end 
  end 
end


if __FILE__ == $0
  require 'lsi_ircu'
  require 'lsi_megacli'
  $in_chef = false
  
  puts "will try #{Crowbar::RAID.controller_styles.join(" ")}"
  Crowbar::RAID.controller_styles.each { |c| 
    puts("trying #{c}")
    @raid = c.new
    test = @raid.find_controller
    if !test.nil?
      puts("using #{c} ") 
      break 
    end
    @raid = nil # nil out if it didn't take     
  }
  puts "no controller " if @raid.nil?  
  
  t = @raid #Crowbar::RAID::LSI_MegaCli.new
  t.load_info
  puts(t.describe_volumes)
  puts(t.describe_disks)  
  t.volumes.each { |x| t.delete_volume(x.vol_id)}
  
  disk_ids = t.disks.map{ |d| "#{d.enclosure}:#{d.slot}"}    
  puts "sleeping for a big"
  sleep 10
  t.create_volume(:RAID10, "dummy", [disk_ids[0]])  
  
end
