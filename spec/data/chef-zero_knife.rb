current_dir = File.dirname(__FILE__)

require "socket"
local_ip = UDPSocket.open {|s| s.connect("8.8.8.8", 1); s.addr.last}

log_level               "info"

chef_server_url         "http://#{local_ip}:9999"
node_name               "stackbuilder_test"
client_key              "#{current_dir}/chef-zero_node.pem"

validation_client_name  "chef-zero_validator"
validation_key          "#{current_dir}/chef-zero_validator.pem"

knife[:berks_knife_config] = __FILE__
