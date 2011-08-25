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

=begin

Sample config block:

{ 
  "vol-raid1" => {:raid_level => :RAID1}, ## must use exactly 2 disks
  "vol-raid0" => {:raid_level => :RAID0, :disks => 3 },
  "default" =>  {:raid_level => :JBOD , :disks => :remaining}
}

=end


def load_current_resource  
  find_controller
  if @raid.nil?
    @failed = true
    return 
  end
  @raid.debug = @new_resource.debug_flag  
  @raid.load_info    
end

action :report do
  begin
    @raid.load_info
    s = "\n"
    s << "Current RAID configuraiton report:\n"
    s << " disks #{@raid.disks.length}: #{@raid.describe_disks}\n"
    s << " volumes: #{@raid.describe_volumes}\n"
    log s
  end unless @failed
end


action :apply do
  apply_config unless @failed  
end

def find_controller
  log("will try #{Crowbar::RAID.controller_styles.join(" ")}")
  Crowbar::RAID.controller_styles.each { |c| 
    log("trying #{c}") {level :debug}
    @raid = c.new
    test = @raid.find_controller
    if !test.nil?
      log("using #{c}") {level :debug}
      break 
    end
    @raid = nil # nil out if it didn't take     
  }
  log("no suported RAID controller found on this system"){level :error} if @raid.nil?    
  
  
end



def apply_config  
  config = @new_resource.config
  errors = validate_config(config)
  
  if errors.length > 0
    log("Config Errors:#{errors}")
    throw "Config error #{errors}"
  end
  
  ##
  # compute delta:  
  #  in:
  #   - @raid.volumes = currently present volumes
  #   - config - desired volumes
  # out:
  #    - missing = volumes we're missing
  #    - keep = volumes we have and we want to keep.
  #    - cur_dup - the volumes we have but don't want   
  keep_vols = []
  missing = []
  cur_dup = @raid.volumes.dup    
  config.each {|name,cfg |  
    next if name.intern == :default  ## skip checking for default...    
    cfg[:vol_name] = name    
    have = cur_dup.select{ |have|
      have.vol_name.casecmp(name) ==0
    }
    if have.length ==0
      missing << cfg 
      log_("will create #{name}")             
    else       
      have_1 = have[0]
      log_("have #{name} #{have_1.raid_level} disks: #{have_1.members.length}") 
      # check config matches, before deciding to keep
      recreate = true
      begin
        log_("wrong raidlevel#{have_1.raid_level}: #{cfg[:raid_level]}") and break unless have_1.raid_level == cfg[:raid_level].intern
        disk_cnt = Float(cfg[:disks]) rescue 0
        log_("wrong disk count") and break if disk_cnt >0 and have_1.members.length != disk_cnt
        recreate = false
        keep_vols << cur_dup.delete(have_1)
      end while false
      if (recreate)
        log_("will recreate #{name}")
        missing << cfg
      else 
        log_("keeping it")
      end
    end
  }
  
  log_("keeping: #{keep_vols.map{|km| km.vol_name}.join(' ')}")  
  log_("missing: #{missing.map{|mm| mm[:vol_name]}.join(' ')}")
  log_("extra: #{cur_dup.map{|dm| dm.vol_name}.join(' ')}")
  
  # see if we have something to do.
  #log_("nothing to be done") and return if missing.length ==0 and cur_dup.length==0
  
  # remove extra
  cur_dup.each {|e| 
    log_("deleting #{e.vol_id}")
    @raid.delete_volume(e.vol_id) 
  }
  
  # figure out what disks we have avail - those not used in volumes we're keeping
  disks_used = keep_vols.map { |v| 
    v.members.map{ |d| "#{d.enclosure}:#{d.slot}"}    
  }
  disks_used.flatten!
  disk_avail = @raid.disks.dup
  disk_avail.delete_if { |d| disks_used.include?("#{d.enclosure}:#{d.slot}") }
  log_("available disks: #{disk_avail.join(',')}")
  
  # allocate disks, and make a list of volumes to create
  missing.sort! { | a,b | a[:order] <=> b[:order] } # sort by order  
  log_(" ordered missing vols: #{missing.map{|m| m[:vol_name]}.join(' ')}")
  missing.each { |m| 
    disk_2_use = []
    disk_cnt = 0
    if m[:disks].nil? or m[:disks] == :remainng
      # use all the disks
      disk_cnt = disk_avail.length
    else
      disk_cnt = Integer(m[:disks])
    end
    disk_cnt = adjust_max_disk_cnt(m,disk_cnt)
     (1..disk_cnt).each {
      disk_2_use << disk_avail.shift rescue throw "out of disks"
    }
    
    log_("Creating vol #{m[:vol_name]} with #{disk_2_use.length} disks: #{disk_2_use.join(' ')}")
    @raid.create_volume(m[:raid_level], m[:vol_name], disk_2_use)
  }
  log_("unused disks #{disk_avail.join(' ')}")
end



=begin
 The following rules need to be checked:  
   - For a type 'RAID1' volume exactly 2 disks must be specified.
   - For a type 'RAID1E' volume min of 3 disks must be specified.
   - For a type 'RAID0' volume min of 2 disks must be specified.
   - For a type 'RAID10' volume min of 4 disks must be specified.
Additionally:
- No set has more than 10 disk
- Raid1E only works with an odd number of disks (so up to 9 total disks, since 10 is not odd)
- No more than 2 raid volumes are specified.
- Total count of disks in config is less than available
- no duplicate named volumes

=end

def validate_config(config)
  
  total_used = 0
  errors = ""
  config.each { |k,v| 
    log("checking volume config: #{k}") {level :warn}    
    err_temp = "#{v[:raid_level]} volume #{k} should "
    v[:disks] = Float(v[:disks]).to_i rescue v[:disks].intern
    case v[:raid_level].intern
      when :RAID1
      errors << err_temp << "have at least 3 disks\n" unless v[:disks].nil? or v[:disks] ==2
      
      when :RAID1E
      errors << err_temp << "have 2 disks\n" unless v[:disks].isblank? or  v[:disks] >2
      errors << err_temp << "have no more than 9 disks\n" unless v[:disks] <=9
      errors << err_temp << "have an odd number of disks\n" unless (v[:disks] % 2) ==1
      v[:disks] = 2
      
      when :RAID0
      errors << err_temp << "have at least 2 disks (#{v[:disks]})\n" unless v[:disks]==:remaining or v[:disks] >= 2
      errors << err_temp << "have no more than 10 disks\n" unless v[:disks] <=10
      
      when :RAID10
      errors << err_temp << "have at least 4 disks\n" unless v[:disks] > 4
      errors << err_temp << "have no more than 10 disks\n" unless v[:disks] <=10
      
      when :JBOD
      
    else
      errors << "#{k} uses an unknwon raid level #{v[:raid_level]}"
    end unless v[:disks] == :remaining
    
    disk_use = Float(v[:disks]) rescue 0
    total_used = total_used + disk_use
    
  }
  
  total_avail = @raid.disks.length
  errors << "too many disks specified. required: #{total_used} avail: #{total_avail}" if total_used > total_avail
  errors  
  
end

=begin
  Check the number of disks to be used, and REDUCE it if it doesn't meet requirements
(can't increase it !)
=end
def adjust_max_disk_cnt(config, s_cnt)
  v = config
  log_pref = "for #{config[:vol_name]} type:#{v[:raid_level]} "
  log ("checking #{log_pref} with #{s_cnt} disks")
  case v[:raid_level].intern
    when :RAID1
    raise "RAID1 - must have 2 disks" if s_cnt < 2
    return 2
    
    when :RAID1E
    raise "RAID1E must have at least 3 disks" if s_cnt < 3
    if s_cnt % 2 ==0
      log("#{log_pref} RAID1E must be odd - reduce by 1") 
      s_cnt = s_cnt -1
    end
    
    s_cnt = 9 if s_cnt > 9     
    
    when :RAID0
    raise "RAID0 must have at least 2 disks" if s_cnt < 2
    if s_cnt >=10
      log("#{log_pref} max disk use is 10") 
      s_cnt = 10
    end
    
    when :RAID10
    raise "RAID10 must have at least 4 disks" if s_cnt < 4
    if s_cnt >=10
      log("#{log_pref} max disk use is 10") 
      s_cnt = 10
    end
    
    when :JBOD
    # no restrictions
  end
  
  return s_cnt
end


def log_(msg)
  Chef::Log.info(msg) 
  true
end
