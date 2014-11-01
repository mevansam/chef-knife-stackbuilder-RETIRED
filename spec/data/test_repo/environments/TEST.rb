name "TEST"
description "Chef 'TEST' environment."

env = YAML.load_file(File.expand_path('../../etc/TEST.yml', __FILE__))

override_attributes(

    'domain' => "#{env['DOMAIN']}",
    'attribA' => {
        'key1' => "#{env['VALUE_A1']}",
        'key2' => "#{env['VALUE_A2']}"
    },
    'attribB' => {
        'key1' => "#{env['VALUE_B1']}",
    }
)
