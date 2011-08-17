# Copyright 2011, Dell
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

=begin
Process a csv file and produce setting maps. The expected format is:

token description set

where set can be:
- y:  include in default
- virt - include in virtualization set
- storage - include in storage set

=end

require 'CSV'
require 'ERB'

class WantMaker
  
  attr_accessor :name
  
  def initialize(fname)
    @fname = fname
    @name = File.basename(fname,'.csv')
    @def_set ={}
    @storage_set ={}
    @virt_set ={}
    
  end
  
  def open
    @data = CSV.read(@fname)
  end
  
  def clean_str(s)
    s.gsub(/[^a-zA-Z_0-9 ]/, "_").strip    
  end
  
  def parse_commands
    
    line_cnt = 0
    cur_opt = nil
    @data.each { | arr |
      line_cnt +=1
      next if line_cnt==1 ## skip headers.
      arr.map! { |x| clean_str(x)}
      val = [ arr[0], arr[2] ]      
      case arr[3]
        when 'y' then  @def_set[arr[1] ] = val  
        when 'virt' then @virt_set [arr[1] ] = val
        when 'storage' then  @storage_set [arr[1] ] = val 
      else
        puts "uknown target set: #{arr[3]} on line #{line_cnt}"       
      end
    }
    
  end
  
  def dump
    
#    puts "default settings: #{@def_set.keys.join(",")}"    
#    puts "virt settings: #{@virt_set.join(",")}"
#    puts "storage settings: #{@storage_set.join(",")}"
    
  end
  
  def erb_comma_helper(set,cnt, out)
    return out if cnt < set.length
    return "" 
  end
  
  def write_result(template, set, name)
    f = File.new("#{name}.json", "w" ) unless name == nil
    f ||= STDOUT
    b = binding    
    c = ERB.new(template, 0, "<%>")
    f.puts(c.result(b))
  end
  
  def create_files     
    open        
    parse_commands
    dump
    base_name = name.split("-")[-1]   
    set_default_name="bios-set-#{base_name}-default"
    set_virt_name= "bios-set-Virtualization-#{base_name}"
    set_storage_name= "bios-set-Storage-#{base_name}" 
    
    write_result(SETTINGS_TEMPLATE,@def_set, set_default_name)    
    write_result(SETTINGS_TEMPLATE,@virt_set, set_virt_name)
    write_result(SETTINGS_TEMPLATE,@storage_set, set_storage_name)
    write_result( REPORT_TEMPLATE, @def_set, nil)
  end
  
end



SETTINGS_TEMPLATE =  <<-TEMP_END
  {  "id": "<%= name %>",
     "attributes": { 
     <% set_cnt=0 ;  set.each { |name, val |
      set_cnt +=1 
     %>   "<%= name %>" : ["<%= val[0]%>", "<%= val[1]%>"] <%= erb_comma_helper(set,set_cnt,',') %>       
     <% } %>}
  }    
TEMP_END


REPORT_TEMPLATE= <<-TEMP_END
<%  set_cnt=0 ;  set.each { |name, val |  %>
  <%= name%> -> <%= val.join("->" ) %> 
  <% } %>  
TEMP_END

if __FILE__ == $0  
  fname = ARGV[0]
  puts "processing #{fname}"
  t = WantMaker.new(fname)
  t.create_files
end
