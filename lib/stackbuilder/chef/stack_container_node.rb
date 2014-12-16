# Copyright (c) 2014 Mevan Samaratunga

include StackBuilder::Common::Helpers

module StackBuilder::Chef

    class ContainerNodeManager < StackBuilder::Chef::NodeManager

        def initialize(id, node_config, repo_path, environment)

            super(id, node_config, repo_path, environment)

            @env_file_path = repo_path + '/environments/' + environment + '.rb'

            @dockerfiles_build_dir = repo_path + '/.build/docker/build'
            FileUtils.mkdir_p(@dockerfiles_build_dir)

            docker_image_dir = repo_path + '/.build/docker/' + environment
            FileUtils.mkdir_p(docker_image_dir)

            docker_image_filename = docker_image_dir + '/' + @name
            @docker_image_path = docker_image_filename + '.gz'
            @docker_image_target = docker_image_filename + '.target'
        end

        def process(index, events, attributes, target = nil)

            target_node_instance = "#{target.node_id}-#{index}"
            node = Chef::Node.load(target_node_instance)
            ipaddress = node.attributes['ipaddress']

            ssh = ssh_create(ipaddress, target.ssh_user,
                target.ssh_password.nil? ? target.ssh_identity_file : target.ssh_password)

            # Copy image file to target if it has changed
            if build_container(attributes) && !target.nil? &&
                ( !File.exist?(@docker_image_target) ||
                (File.mtime(@docker_image_path) > File.mtime(@docker_image_target)) )

                puts "Uploading docker image to target '#{target_node_instance}'."
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

                FileUtils.touch(@docker_image_target)
            end

            # Start container instances
            if @knife_config.has_key?('container_start')

                result = ssh_exec!(ssh, "sudo docker ps -a | awk '/#{@node_id}/ { print $0 }'")
                raise StackBuilder::Common::StackBuilderError, "Error determining running containers for #{@name}: #{result[:err]}" \
                    if result[:exit_code]>0

                running_instances = result[:out].lines
                if running_instances.size > @scale

                    (running_instances.size - 1).downto(@scale) do |i|

                        container_node_id = "#{@node_id}-#{i}"
                        running_instance = running_instances.select{ |ri| ri[/#{@node_id}-\d+/,0]==container_node_id }
                        container_id = running_instance.first[/^[0-9a-z]+/,0]

                        result = ssh_exec!(ssh, "sudo docker rm -f #{container_id}")

                        if result[:exit_code]==0

                            container_port_map = Hash.new
                            container_port_map.merge!(node.normal['container_port_map']) \
                                unless node.normal['container_port_map'].nil?

                            container_port_map.each do |k,v|
                                container_port_map[k].delete(container_id)
                            end

                            node.normal['container_port_map'] = container_port_map
                            node.save

                            knife_cmd = Chef::Knife::NodeDelete.new
                            knife_cmd.name_args = [ container_node_id ]
                            knife_cmd.config[:yes] = true
                            run_knife(knife_cmd)

                            knife_cmd = Chef::Knife::ClientDelete.new
                            knife_cmd.name_args = [ container_node_id ]
                            knife_cmd.config[:yes] = true
                            run_knife(knife_cmd)
                        else
                            @logger.error("Unable to stop container instance #{running_instances[i]}: #{result[:err]}")
                        end
                    end

                elsif running_instances.size < @scale

                    container_start = @knife_config['container_start']
                    container_ports = container_start['ports']
                    container_options = container_start['options']

                    start_cmd = "sudo docker run -d "

                    start_cmd += container_options \
                        unless container_options.nil?

                    start_cmd += container_ports.collect \
                        { |k,p| "-p :#{p=~/\d+\:\d+/ ? p.to_s : ':' + p.to_s}" }.join(' ') \
                        unless container_ports.nil?

                    running_instances.size.upto(@scale - 1) do |i|

                        container_node_id = "#{@node_id}-#{i}"

                        result = ssh_exec!( ssh,
                            "#{start_cmd} --name #{container_node_id} " +
                            "-e \"CHEF_NODE_NAME=#{container_node_id}\" #{@name}")

                        if result[:exit_code]==0

                            # Actual container id is the first 12 chars
                            container_id = result[:out][0, 12]

                            container_port_map = Hash.new
                            container_port_map.merge!(node.normal['container_port_map']) \
                                unless node.normal['container_port_map'].nil?

                            container_ports.each do |k,p|

                                port_map = container_port_map[k]
                                if port_map.nil?

                                    port_map = { }
                                    container_port_map[k] = port_map
                                end

                                if p=~/\d+\:\d+/
                                    port_map[container_id] = p[/(\d+)\:\d+/, 1]
                                else
                                    result = ssh_exec!(ssh, "sudo docker port #{container_node_id} #{p}")

                                    @logger.error( "Unable to get host port for " +
                                        "'#{@node_id}-#{i}:#{p}': #{result[:err]}") \
                                        if result[:exit_code]>0

                                    port_map[container_id] = result[:out][/:(\d+)$/, 1]
                                end
                            end

                            node.normal['container_port_map'] = container_port_map
                            node.save
                        else
                            @logger.error("Unable to start container instance '#{@node_id}-#{i}': #{result[:err]}")
                        end
                    end
                end

            end

            super(index, events, attributes, target)
        end

        def delete(index)

            super(index)
        end

        private

        def build_container(attributes)

            @@sync ||= Mutex.new
            @@sync.synchronize {

                unless @build_complete ||
                    ( File.exist?(@docker_image_path) && File.exist?(@env_file_path) && \
                    File.mtime(@docker_image_path) > File.mtime(@env_file_path) )

                    %x(docker images)
                    raise ArgumentError, "Docker does not appear to be available." unless $?.success?

                    if is_os_x? || !is_nix_os?

                        raise ArgumentError, "DOCKER_HOST environment variable not set." \
                            unless ENV['DOCKER_HOST']
                        raise ArgumentError, "DOCKER_CERT_PATH environment variable not set." \
                            unless ENV['DOCKER_CERT_PATH']
                        raise ArgumentError, "DOCKER_TLS_VERIFY environment variable not set." \
                            unless ENV['DOCKER_TLS_VERIFY']
                    end

                    echo_output = @logger.info? || @logger.debug?
                    build_exists = @name==`docker images | awk '/#{@name}/ { print $1 }'`.strip

                    knife_cmd = Chef::Knife::ContainerDockerInit.new

                    # Run as a forked job (This captures all output and removes noise from output)
                    job_handles = run_jobs(knife_cmd) do |k|

                        k.name_args = [ @name ]

                        k.config[:local_mode] = false
                        k.config[:base_image] = build_exists ? @name : @knife_config['image']
                        k.config[:force] = true
                        k.config[:generate_berksfile] = false
                        k.config[:include_credentials] = true

                        k.config[:dockerfiles_path] = @dockerfiles_build_dir
                        k.config[:run_list] = @knife_config['run_list']

                        k.config[:encrypted_data_bag_secret] = IO.read(@env_key_file) \
                            unless File.exist? (@env_key_file)

                        run_knife(k)
                    end
                    wait_jobs(job_handles)

                    dockerfiles_named_path = @dockerfiles_build_dir + '/' + @name

                    # Create env key to add to the docker image
                    FileUtils.cp(@env_key_file, dockerfiles_named_path + '/chef/encrypted_data_bag_secret')

                    if @knife_config.has_key?('inline_dockerfile')

                        dockerfile_file = dockerfiles_named_path + '/Dockerfile'
                        dockerfile = IO.read(dockerfile_file).lines

                        dockerfile_new = [ ]

                        log_level = (
                            @logger.debug? ? 'debug' :
                            @logger.info? ? 'info' :
                            @logger.warn? ? 'warn' :
                            @logger.error? ? 'error' :
                            @logger.fatal? ? 'fatal' : 'error' )

                        while dockerfile.size>0
                            l = dockerfile.delete_at(0)

                            if l.start_with?('RUN chef-init ')
                                # Ensure node builds with the correct Chef environment and attributes
                                dockerfile_new << l.chomp + " -E #{@environment} -l #{log_level}\n"

                            elsif l.start_with?('CMD ')
                                # Ensure node starts within the correct Chef environment and attributes
                                dockerfile_new << l.gsub(/\"\]/,"\",\"-E #{@environment}\"]")

                            else
                                dockerfile_new << l

                                if l.start_with?('FROM ')
                                    # Insert additional custom Dockerfile build steps
                                    dockerfile_new += @knife_config['inline_dockerfile'].lines.map { |ll| ll.strip + "\n" }
                                end
                            end
                        end
                        dockerfile_new += dockerfile

                        File.open(dockerfile_file, 'w+') { |f| f.write(dockerfile_new.join) }
                    end

                    # Add container services
                    if @knife_config.has_key?('container_service')

                        first_boot_file = dockerfiles_named_path + '/chef/first-boot.json'
                        first_boot = JSON.load(File.new(first_boot_file, 'r')).to_hash

                        first_boot.merge!(attributes)
                        first_boot['container_service'] = @knife_config['container_service']

                        File.open(first_boot_file, 'w+') { |f| f.write(first_boot.to_json) }
                    end

                    knife_cmd = Chef::Knife::ContainerDockerBuild.new

                    # Run as a forked job (This captures all output and removes noise from output)
                    job_handles = run_jobs(knife_cmd, echo_output) do |k|

                        k.name_args = [ @name ]

                        k.config[:run_berks] = false
                        k.config[:force_build] = true
                        k.config[:dockerfiles_path] = @dockerfiles_build_dir
                        k.config[:cleanup] = true

                        run_knife(k)
                    end
                    job_results = wait_jobs(job_handles)

                    if job_results[knife_cmd.object_id][0]
                        .rindex('Chef run process exited unsuccessfully (exit code 1)')

                        if @logger.level>=::Logger::WARN
                            puts "Knife container build Chef convergence failed with an error."
                            puts "#{job_results.first[0]}"
                        end

                        %x(
                            for i in $(docker ps -a | awk '/chef-in/ { print $1 }'); do docker rm -f $i; done
                            for i in $(docker images | awk '/<none>/ { print $3 }'); do docker rmi $i; done
                        )

                        raise StackBuilder::Common::StackBuilderError, "Docker build of container #{@name} has errors."
                    end

                    puts 'Saving docker image for upload. This may take a few minutes.'
                    out = %x(docker save #{@name} | gzip -9 > #{@docker_image_path})

                    raise StackBuilder::Common::StackBuilderError, \
                        "Unable to save docker container #{@name}: #{out}" unless $?.success?
                end
            }

            @build_complete = true
        end

    end
end
