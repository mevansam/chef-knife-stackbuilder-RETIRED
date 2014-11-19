current_dir = File.dirname(__FILE__)

log_level               "info"

chef_server_url         "http://127.0.0.1:9999"
node_name               "stackbuilder_test"
client_key              "#{current_dir}/chef-zero_node.pem"

validation_client_name  "chef-zero_validator"
validation_key          "#{current_dir}/chef-zero_validator.pem"
