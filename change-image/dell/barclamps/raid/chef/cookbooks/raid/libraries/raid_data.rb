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


####
# Some common data structures used by all RAID support libraries


class Crowbar
  class RAID
    
    RAID0 = :RAID0
    RAID1 = :RAID1      
    RAID1E = :RAID1E
    RAID10 = :RAID10
    JBOD = :JBOD
    
    class Volume
      attr_accessor :vol_name, :vol_id, :raid_level, :members, :name , :os_dev, :size
      attr_accessor :pci_id ## seems to be the main connection between volumes and OS device names
            
      def initialize
        @members = []
      end
      
      def to_s
        "id: #{vol_id} name: #{vol_name} type: #{raid_level} members:{ #{members.join(",")} }"
      end
      
    end
    
    class RaidDisk
      attr_accessor :disk_id, :enclosure ,:slot
      
      def to_s
        "#{enclosure}:#{slot}"
      end
      
    end
    
    class OSDisk
      attr_accessor :pci_id, :dev_name
    end    
  end
end

