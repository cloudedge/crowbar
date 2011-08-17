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


require File.join(File.dirname(__FILE__), 'd4_tokenizer' )

dir = File.dirname(__FILE__)

Dir.chdir(dir) { |d|
  puts "working in #{dir}\n"
  Dir["maps/*.csv"].each { |f|
    puts "processing in #{f}\n"
    D4Tokenizer.create_files(f)              
  }
}



