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
This little utility reads a CSV file (like the ones in the maps directory) which describe the available D4 tokens used to 
configure BIOS options, and creates the following artifacts:  
- bios-map-XXX.json - describes the D4 tokens in the following format:
   Setting => { option -> D4 Token }*

- bios-map-XXX.schema - a schema to validate settings files against.



=end
require 'CSV'
require 'ERB'

class D4Tokenizer
  
  class OptionSettings
    attr_accessor :opts, :name, :default
    
    def initialize(name)
      @name = name.strip.gsub(/\s+/,'_')      
    end
    
    def add_opt(name, d4)
      @opts ||= {}      
      @opts[name.strip] = d4.strip
    end
    
    def validate(err)
      return if @default.nil?
      ## check that the default is one of the valid options
      err << "#{@name} doesn't have value for default #{@default} \n"  unless @opts.has_key?(@default)      
    end
    
    def dump
      @opts.each { |name, opt |
        puts  "  option #{name}" << " D4: #{opt} \n"
      }      
    end    
  end
  
  attr_accessor :name
  
  def initialize(fname)
    @fname = fname
    @name = File.basename(fname,'.csv')
  end
  
  def open
    @data = CSV.read(@fname)
  end
  
  def parse_commands
    @settings = {}
    line_cnt = 0
    cur_opt = nil
    @data.each { | arr |
      line_cnt +=1
      next if arr[6].nil?  # doesn't have D4 tokens
      next if !arr[7].nil? and arr[7].match(/PUMA/)  # ignore options only avail for PUMA      
      opt_name = arr[3]
      opt_name ||= arr[2]
      opt_name ||= arr[1]      
      if !opt_name.nil?
        #puts "found new option: #{opt_name}"
        @settings [cur_opt.name] = cur_opt unless cur_opt.nil? or cur_opt.opts.length ==0       
        cur_opt = OptionSettings.new(opt_name)
        cur_opt.default = $1 if !arr[4].nil? and arr[4].match(/^\s*\[(.*)\]\s*$/)
      end
      next if cur_opt.nil?
      
      #puts "input:#{arr.join("|")}} \n"
      names = [ arr[1] ]
      names = arr[5].split('/') unless arr[5].nil?
      cmds = arr[6].split('/')    
       (0..names.length-1).each { |idx|
        n = names[idx]
        c = cmds[idx]
        if (c =~ /(.*)\((.*)\)/)
          n = $1
          c = $2 
          puts "parsing () style: #{n}, #{c}"
        else 
          puts "parsing / style #{n}, #{c}"
        end
        puts "failed to parse: #{n}, #{c} " && next if n.nil? or c.nil?
        cur_opt.add_opt(n,c)
      }
    }
    
    valid_errs = ""
    @settings.each{ |name,set| 
      set.validate valid_errs
    }
    raise valid_errs if  valid_errs.length > 0 
    
  rescue
    puts "failed in line #{line_cnt}"
    raise 
  end
  
  def dump    
    @opts.each { |name, opts | 
      puts " name: #{name}"
      opts.dump
    }
  end
  
  def erb_comma_helper(set,cnt, out)
    return out if cnt < set.length
    return "" 
  end
  
  def write_result(f,template, name)  
    b = binding
    c = ERB.new(template, 0, "<%>")
    f.puts(c.result(b))
  end
   
  def self.create_files(name)
    t = D4Tokenizer.new(name) 
    t.open        
    t.parse_commands
    base_name = t.name.split("-")[-1]   
    map_name="bios-map-#{base_name}"
    set_schema_name="bios-set-#{base_name}"
    set_default_name="bios-set-#{base_name}-default"
    target_file= File.new("#{map_name}.json", "w" )
    target_schema= File.new("#{set_schema_name}.schema", "w" )
    target_deault= File.new("#{set_default_name}.json", "w" )
    t.write_result(target_file,JSON_TEMPLATE,map_name)
    t.write_result(target_schema,SCHEMA_TEMPLATE,set_schema_name)
    t.write_result(target_deault,SETTINGS_TEMPLATE,set_default_name)    
    t.write_result(STDOUT, REPORT_TEMPLATE, "stdout report")
  end
  
end


JSON_TEMPLATE = <<-TEMP_END
  {  "id": "<%= name %>",
     "attributes": { <%  set_cnt=0 ; @settings.each { | name, set | %> 
        "<%= name %>" : { 
          <% cnt = 0;  set.opts.each { | name,addr| %> "<%= name %>": "<%= addr %>"<% cnt +=1 %><%= erb_comma_helper(set.opts.keys,cnt,',') %><% } %> 
        }  <% set_cnt += 1%> <%= erb_comma_helper(@settings,set_cnt,',') %>     
     <% } %>}
  }    
  TEMP_END



SCHEMA_TEMPLATE = <<-TEMP_END
{ 
  "type" : "map", "required": true, "mapping":  {  
     "id" : { "type": "str", "required": true } ,  
     "attributes" : { "type": "map", "required": true, "mapping":  {
         <% set_cnt=0 ; @settings.each { | name, set | %>
         "<%= name %>" : { "type" : "str", "required": false, "pattern": "/^<% cnt = 0;  set.opts.each { | name,addr| %><%= name%><% cnt =cnt+1 %><%=erb_comma_helper(set.opts.keys,cnt,'|') %><% } %>/" }<% set_cnt=set_cnt+1 %><%= (set_cnt < @settings.length ) ? "," : "" %> 
         <%} %>        
        }
      }
   }     
} 
TEMP_END

SETTINGS_TEMPLATE =  <<-TEMP_END
  {  "id": "<%= name %>",
     "attributes": { 
     <% set_cnt=0 ;  @settings.each { | name, set |
      set_cnt +=1 
      next if set.default.nil?
     %>   "<%= name %>" : "<%= set.default %>"<%= erb_comma_helper(@settings,set_cnt,',') %>       
     <% } %>}
  }    
TEMP_END


REPORT_TEMPLATE= <<-TEMP_END
<% @settings.each { | name, set |
  set.opts.each { | name,addr| %> 
  <%= addr %>,
  <% } 
  } %>  
}

TEMP_END

if __FILE__ == $0  
  fname = ARGV[0]
  puts "processing #{fname}"
  D4Tokenizer.create_files(fname)
end
