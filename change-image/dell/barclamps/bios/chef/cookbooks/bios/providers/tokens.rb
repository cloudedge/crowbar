
# Copyright 2011, Dell



def load_current_resource
  t_lst = %x{/usr/sbin/setupbios list_tokens}
  @@tokens = []
  t_lst.each { |x|
    sp = x.split()
    @@tokens << sp[6] unless sp[6].nil?
  }
end 



action :dump do 
  s = ""
  @@tokens.each { |t| 
    cmd = "/usr/sbin/setupbios test #{t}"
    val = %x{ #{cmd} }
    s << "t: #{t} #{val}"  
  }
  Chef::Log.warn("Current token state: #{@new_resource.name} \n #{s}")
end
