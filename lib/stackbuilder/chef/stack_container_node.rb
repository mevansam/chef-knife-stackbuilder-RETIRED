# Copyright (c) 2014 Mevan Samaratunga

include StackBuilder::Common::Helpers

module StackBuilder::Chef

    class ContainerNodeManager < StackBuilder::Chef::NodeManager

        def initialize(id, node_config, repo_path, environment)

            super(id, node_config, repo_path, environment)

            @env_file_path = repo_path + '/environments/' + environment + '.rb'

            docker_image_dir = repo_path + '/.docker_images'
            FileUtils.mkdir_p(docker_image_dir)
            @docker_image_path = docker_image_dir + '/' + @name + '.gz'
        end

        def process(index, events, attributes, target = nil)

            @@sync ||= Mutex.new
            @@sync.synchronize {

                unless @build_complete ||
                    (File.exist?(@docker_image_path) && File.exist?(@env_file_path) && \
                    File.mtime(@docker_image_path) > File.mtime(@env_file_path) )

                    if is_os_x? || !is_nix_os?

                        raise ArgumentError, "DOCKER_HOST environment variable not set." \
                            unless ENV['DOCKER_HOST']
                        raise ArgumentError, "DOCKER_CERT_PATH environment variable not set." \
                            unless ENV['DOCKER_CERT_PATH']
                        raise ArgumentError, "DOCKER_TLS_VERIFY environment variable not set." \
                            unless ENV['DOCKER_TLS_VERIFY']
                    end

                    begin
                        build_role = Chef::Role.new
                        build_role.name(@name + '_build')
                        build_role.override_attributes(attributes)
                        build_role.save

                        dockerfiles_path = File.join(Dir.home, '/.knife/container')

                        build_exists = @name==`docker images | awk '/#{@name}/ { print $1 }'`.strip

                        knife_cmd = Chef::Knife::ContainerDockerInit.new
                        knife_cmd.name_args = [ @name ]

                        knife_cmd.config[:local_mode] = false
                        knife_cmd.config[:base_image] = build_exists ? @name : @knife_config['image']
                        knife_cmd.config[:force] = true
                        knife_cmd.config[:generate_berksfile] = false
                        knife_cmd.config[:include_credentials] = false

                        knife_cmd.config[:dockerfiles_path] = dockerfiles_path
                        knife_cmd.config[:run_list] = @knife_config['run_list'] + [ "role[#{build_role.name}]" ]

                        knife_cmd.config[:encrypted_data_bag_secret] = IO.read(@env_key_file) \
                            unless File.exist? (@env_key_file)

                        run_knife(knife_cmd)

                        if @knife_config.has_key?('inline_dockerfile')

                            dockerfile_path = dockerfiles_path + "/#{@name}/Dockerfile"
                            docker_file = IO.read(dockerfile_path).lines

                            docker_file_new = [ ]
                            while docker_file.size>0
                                l = docker_file.delete_at(0)
                                docker_file_new << l
                                if l.start_with?('FROM ')
                                    docker_file_new += @knife_config['inline_dockerfile'].lines.map { |ll| ll.strip + "\n" }
                                    break
                                end
                            end
                            docker_file_new += docker_file

                            File.open(dockerfile_path, 'w+') { |f| f.write(docker_file_new.join) }
                        end

                        knife_cmd = Chef::Knife::ContainerDockerBuild.new
                        knife_cmd.name_args = [ @name ]

                        knife_cmd.config[:run_berks] = false
                        knife_cmd.config[:force_build] = true
                        knife_cmd.config[:dockerfiles_path] = dockerfiles_path
                        knife_cmd.config[:cleanup] = true

                        result = run_knife(knife_cmd)

                    ensure
                        build_role.destroy unless build_role.nil?
                    end

                    # TODO: Errors are currently not detected as knife-container sends all chef-client output to stdout
                    if result.rindex('Chef run process exited unsuccessfully (exit code 1)')

                        if @logger.level>=::Logger::WARN
                            puts "Knife execution failed with an error."
                            puts "#{result.string}"
                        end

                        `for i in $(docker ps -a | awk '/chef-in/ { print $1 }'); do docker rm -f $i; done`
                        `for i in $(docker images | awk '/<none>/ { print $3 }'); do docker rmi $i; done`

                        raise StackBuilderError, 'Container build has errors.'
                    end

                    `docker save #{@name} | gzip -9 > #{@docker_image_path}`
                end
                @build_complete = true
            }

            if @build_complete && !target.nil?

                node = Chef::Node.load("#{target.node_id}-#{index}")
                ipaddress = node.attributes['ipaddress']

                if target.ssh_password.nil?
                    ssh = Net::SSH.start(ipaddress, target.ssh_user,
                        {
                              :key_data => IO.read(target.ssh_identity_file),
                              :user_known_hosts_file => "/dev/null"
                        } )
                else
                    ssh = Net::SSH.start(ipaddress, target.ssh_user,
                        {
                              :password => target.ssh_password,
                              :user_known_hosts_file => "/dev/null"
                        } )
                end

                ssh.open_channel do |channel|

                    channel.exec('gunzip | sudo docker load') do |ch, success|
                        channel.on_data do |ch, data|
                            res << data
                        end

                        channel.send_data IO.binread(@docker_image_path)
                        channel.eof!
                    end
                end
                ssh.loop
            end

            super(index, events, attributes, target)
        end


    end
end
