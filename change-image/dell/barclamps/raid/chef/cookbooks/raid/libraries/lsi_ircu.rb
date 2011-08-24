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

require 'pty'
$in_chef = true
if __FILE__ == $0
  require 'raid_data'
  in_chef = false
end


class Crowbar
  class RAID
    class LSI_sasIrcu
  
  attr_accessor :disks, :volumes, :debug
  CMD = '/updates/sas2ircu'
  RAID_MAP = {
    "RAID0" => :RAID0,
    "RAID1" => :RAID1,
    "RAID1E" => :RAID1E,
    "RAID10" => :RAID10
  }  
  
  def initialize
    find_controller    
    @@re_lines = /^-+$/
    @debug = false
  end
  
  def find_controller
    @cntrl_id =0  # seems that if there's just 1, it's always 0..
  end
  
  def load_info    
    lines = run_tool(["display"])
    phyz = find_stanza lines,"Physical device information"
    logical = find_stanza lines, "IR Volume information"
    
    @disks = parse_dev_info phyz
    @volumes = parse_vol_info logical
  end
  
  def describe_volumes
    load_info if @volumes.nil?
    s = ""
    @volumes.each { |v| s << v.to_s << " "}
    s
  end
  
  def describe_disks
    load_info if @disks.nil?
    s = ""
    @disks.each { |d| s << d.to_s << " " }
    s
  end
  
  
=begin
Issue the command to create a RAID volue:
 The format of the CREATE command is
   sas2ircu <controller #> create <volume type> <size>
   <Encl:Bay> [Volume Name] [noprompt]
    where <controller #> is:
        A controller number between 0 and 255.
    where <volume type> is:
        The type of the volume to create and is either RAID1 (or)
        RAID1E (or) RAID0 (or) RAID10.
    where <size> is:
        The size of the volume to create. It should be given in Mbytes
        e.g. 2048 or 'MAX' to use the maximum size possible.
    where <Encl:Bay> is:
        A list of Encl:Bay pairs identifying the disk drives you
        wish to include in the volume being created. If the volume type is
        'RAID1', the first drive will be selected as the primary and the
        second as the secondary drive.
        For a type 'RAID1' volume exactly 2 disks must be specified.
        For a type 'RAID1E' volume min of 3 disks must be specified.
        For a type 'RAID0' volume min of 2 disks must be specified.
        For a type 'RAID10' volume min of 4 disks must be specified.
    where [Volume Name] is an optional argument that can be used
        to identify a Volume with a user specified Alpha-numeric string
    where noprompt is an optional argument that eliminates
        warnings and prompts

=end  
  def create_volume(type, name, disk_ids )
    ## build up the command...     
    text = ""
    run_tool(["create", type.to_s, "MAX", disk_ids, "'#{name}'","noprompt"]){ |f| 
      text = f.readlines
    }
    text.to_s.strip
  rescue
    Chef::Log.error("create returned: #{text}")
    raise 
  end
  
  def delete_volume(id)
    text = ""
    run_tool(["delete", id, "noprompt"]) { |f|
      text = f.readlines
    }
  rescue
    Chef::Log.error("delete returned: #{text}")
    raise 
  end
  
=begin  

IR volume 1
  Volume ID                               : 172
  Volume Name                             : crowbar-RAID1
  Status of volume                        : Okay (OKY)
  RAID level                              : RAID1
  Size (in MB)                            : 952720
  Physical hard disks                     :
  PHY[0] Enclosure#/Slot#                 : 2:10
  PHY[1] Enclosure#/Slot#                 : 2:11
=end
  
  def parse_vol_info(lines)
    vols= []
    begin
      skip_to_find lines,/^IR volume (\d+)\s*/
      break if lines.length ==0
      lines.shift
      
      rv = Crowbar::RAID::Volume.new
      rv.vol_id=extract_value(lines.shift)
      rv.vol_name =extract_value(lines.shift)
      lines.shift
      #      skip_to_find lines, /\s+RAID level\s*:\s*$/
      raid_level =extract_value(lines.shift)
      rv.raid_level=RAID_MAP[raid_level]
      
      skip_to_find lines,/\s+Physical hard disks\s*:\s*$/
      lines.shift
      disk_re = /\s+PHY.* : (\d+):(\d+)\s*$/
      begin
        rd = Crowbar::RAID::RaidDisk.new
        rd.enclosure, rd.slot = rv.name =disk_re.match(lines.shift)[1,2]
        rv.members << rd
      end while lines.length > 0 and disk_re.match(lines[0])
      vols << rv
    end while lines.length > 0      
    vols
  end
  
=begin
Parse out disk info. Needed to create raid sets (enclosure and slot)

Device is a Hard disk
  Enclosure #                             : 2
  Slot #                                  : 11
  SAS Address                             : 500065b-0-0003-0000
  State                                   : Optimal (OPT)
  Size (in MB)/(in sectors)               : 953869/1953525167
  Manufacturer                            : ATA
  Model Number                            : ST31000524NS
  Firmware Revision                       : KA05
  Serial No                               : 9WK3CWZJ
  Protocol                                : SATA
  Drive Type                              : SATA_HDD

=end
  
  def parse_dev_info(lines)
    disks = []
    begin
      skip_to_find lines,/^Device is a Hard disk\s*/
      break if lines.length ==0
      lines.shift      
      rd = Crowbar::RAID::RaidDisk.new
      rd.enclosure = extract_value(lines.shift)
      rd.slot =extract_value(lines.shift)
      disks<<rd      
    end while lines.length > 0
    disks    
  end
  
  
  
  def extract_value(line, re = /\s+(.*)\s+:(.*)\s*$/)
    re.match(line)
    $2.strip unless $2.nil?
  end
  
  
=begin
  Output from the LSI util is broken into stanzas delineated with something like:
------------------------------------------------------------------------
Controller information
------------------------------------------------------------------------

This method finds a stanza by name and returns an array with its content 
=end  
  
  def find_stanza(lines,name)
    lines = lines.dup
    begin
      # find a stanza mark.
      skip_to_find lines,@@re_lines
      lines.shift
      #make sure it's the right one.
    end while lines.length > 0 and  lines[0].strip.casecmp(name) != 0 
    lines.shift # skip stanza name and marker
    lines.shift
    log("start of #{name} is #{lines[0]}")
    
    #lines now starts with the right stanzs.... filter out the rest.    
    ours = skip_to_find lines,@@re_lines    
    ours    
  end
  
  def skip_to_find(lines, re)
    skipped = []
    skipped << lines.shift while lines.length > 0 and re.match(lines[0]).nil?
    log("first line is:#{lines[0].nil? ? '-' : lines[0]}")
    skipped
  end
  
    def run_tool (args, &block)    
    cmd = [CMD, @cntrl_id, *args].join(" ")
    log "will execute #{cmd}"
    if block_given?
      ret = IO.popen(cmd,&block)            
      log ("return code is #{$?}")          
      raise "cmd #{cmd} returned #{$?}" unless $? ==0 
      return ret
    else
      text = ""
      IO.popen(cmd) {|f|                
        text = f.readlines  
      }
      raise "cmd #{cmd} returned #{$?}" unless $? ==0
    end
    text
  end

  def log(msg)
    return unless @debug
    if $in_chef
      Chef::Log.info(msg)
    else
      puts msg
    end

    true
  end
  
    end
  end
end




if __FILE__ == $0
  l = Crowbar::RAID::LSI_sasIrcu.new
  l.load_info
  
  ids = disks[0..11].map {|x | "%s:%s" % [x.enclosure,x.slot] }.join(" ")
  l.create_volume Crowbar::RAID::RAID10, "crw-raid1e", ids
  #l.create_volume Crowbar::RAID::RAID1E, "crw-raid1e", l.disks[5..9]
end
