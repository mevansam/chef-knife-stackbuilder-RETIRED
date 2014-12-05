# Copyright (c) 2014 Mevan Samaratunga

include StackBuilder::Common::Helpers

module StackBuilder::Chef

    class RepoNotFoundError < StackBuilder::Common::StackBuilderError; end
    class InvalidRepoError < StackBuilder::Common::StackBuilderError; end

    class Repo

        include ERB::Util

        attr_reader :environments

        REPO_DIRS = [
                'etc',
                'cookbooks',
                'environments',
                'secrets',
                'data_bags',
                'roles'
            ]

        def initialize(path, certificates = nil, environments = nil, cookbooks = nil)

            raise StackBuilder::Common::StackBuilderError, "Repo path cannot be nil." if path.nil?

            @logger = StackBuilder::Common::Config.logger
            @repo_path = File.expand_path(path)

            if Dir.exist?(@repo_path)

                REPO_DIRS.each do |folder|

                    next if [ 'cookbooks' ].include?(folder)

                    repo_folder = "#{@repo_path}/#{folder}"
                    raise InvalidRepoError,
                          "Repo folder #{repo_folder} is missing" unless Dir.exist?(repo_folder)
                end

                @environments = [ ]
                Dir["#{@repo_path}/environments/**/*.rb"].each do |envfile|
                    @environments << envfile[/\/(\w+).rb$/, 1]
                end

                @logger.debug("Found stack environments #{@environments}")
            else
                raise RepoNotFoundError,
                      "Unable to load repo @ #{@repo_path}. If you need to create a repo please " +
                      "provide the list of environments at a minimum" if environments.nil?

                REPO_DIRS.each do |folder|
                    system("mkdir -p #{@repo_path}/#{folder}")
                end

                # Create Berksfile
                @berks_cookbooks = cookbooks.nil? ? [] : cookbooks.split(',').map { |s| s.strip.split(':') }
                berksfile_template = IO.read(File.expand_path('../../resources/Berksfile.erb', __FILE__))

                berksfile = ERB.new(berksfile_template, nil, '-<>').result(binding)
                File.open("#{@repo_path}/Berksfile", 'w+') { |f| f.write(berksfile) }

                # Create Environments and Stacks
                @environments = environments.split(',').map { |s| s.strip }
                configfile_template = IO.read(File.expand_path('../../resources/Config.yml.erb', __FILE__))
                envfile_template = IO.read(File.expand_path('../../resources/Environment.rb.erb', __FILE__))
                stackfile_template = IO.read(File.expand_path('../../resources/Stack.yml.erb', __FILE__))

                i = 1
                @environments.each do |env_name|

                    @environment = env_name

                    configfile = ERB.new(configfile_template, nil, '-<>').result(binding)
                    File.open("#{@repo_path}/etc/#{env_name}.yml", 'w+') { |f| f.write(configfile) }

                    envfile = ERB.new(envfile_template, nil, '-<>').result(binding)
                    File.open("#{@repo_path}/environments/#{env_name}.rb", 'w+') { |f| f.write(envfile) }

                    stackfile = ERB.new(stackfile_template, nil, '-<>').result(binding)
                    File.open("#{@repo_path}/stack#{i}.yml", 'w+') { |f| f.write(stackfile) }
                    i += 1
                end
                @environment = nil

                # Create or copy certs
                create_certs(certificates) unless certificates.nil?
            end
        end

        def upload_environments(environment = nil)

            environments = (environment.nil? ? @environments : [ environment ])
            knife_cmd = Chef::Knife::EnvironmentFromFile.new

            environments.each do |env_name|

                # TODO: Handle JSON environment files. JSON files should be processed similar to roles.

                knife_cmd.name_args = [ "#{@repo_path}/environments/#{env_name}.rb" ]
                run_knife(knife_cmd)
                puts "Uploaded environment '#{env_name}' to '#{Chef::Config.chef_server_url}'."
            end
        end

        def upload_certificates(environment = nil, server = nil)

            create_certs(server) unless server.nil?

            knife_cmd = Chef::Knife::DataBagList.new
            data_bag_list = run_knife(knife_cmd).split

            # Create environment specific data bags to hold certificates
            @environments.each do |env_name|

                data_bag_env = 'certificates-' + env_name
                unless data_bag_list.include?(data_bag_env)
                    knife_cmd = Chef::Knife::DataBagCreate.new
                    knife_cmd.name_args = data_bag_env
                    run_knife(knife_cmd)
                end
            end

            Dir["#{@repo_path}/.certs/*"].each do |server_cert_dir|

                if File.directory?(server_cert_dir)

                    s = server_cert_dir.split('/').last

                    server_env_name = s[/.*_(\w+)$/, 1]
                    server_name = server_env_name.nil? ? s : s[/(.*)_\w+$/, 1]

                    if server.nil? || server==server_name

                        if server_env_name.nil?

                            environments = (environment.nil? ? @environments : [ environment ])
                            environments.each do |env_name|
                                upload_certificate(server_cert_dir, server_name, env_name)
                            end

                        elsif environment.nil? || environment==server_env_name
                            upload_certificate(server_cert_dir, server_name, server_env_name)
                        end
                    end
                end
            end
        end

        def upload_data_bags(environment = nil, data_bag = nil)

            environments = (environment.nil? ? @environments : [ environment ])

            knife_cmd = Chef::Knife::DataBagList.new
            data_bag_list = run_knife(knife_cmd).split

            Dir["#{@repo_path}/data_bags/*"].each do |data_bag_dir|

                data_bag_name = data_bag_dir[/\/(\w+)$/, 1]
                if data_bag.nil? || data_bag==data_bag_name

                    environments.each do |env_name|

                        data_bag_env = data_bag_name + '-' + env_name
                        unless data_bag_list.include?(data_bag_env)
                            knife_cmd = Chef::Knife::DataBagCreate.new
                            knife_cmd.name_args = data_bag_env
                            run_knife(knife_cmd)
                        end

                        env_file = "#{@repo_path}/etc/#{env_name}.yml"
                        env_vars = File.exist?(env_file) ?
                            StackBuilder::Common.load_yaml("#{@repo_path}/etc/#{env_name}.yml", ENV) : { }

                        secret = get_secret(env_name)

                        upload_data_bag_items(secret, data_bag_dir, data_bag_env, env_vars)

                        env_item_dir = data_bag_dir + '/' + env_name
                        upload_data_bag_items(secret, env_item_dir, data_bag_env, env_vars) if Dir.exist?(env_item_dir)
                    end
                end
            end
        end

        def upload_cookbooks(cookbook = nil, upload_options = '--no-freeze')

            berksfile_path = "#{@repo_path}/Berksfile"
            debug_flag = (@logger.debug? ? ' --debug' : '')

            # Need to invoke Berkshelf from the shell as directly invoking it causes
            # cookbook validation to throw an exception when 'Berksfile.upload' is
            # called.
            #
            # TBD: More research needs to be done as direct invocation is preferable

            cmd = ""

            cmd += "export BERKSHELF_CHEF_CONFIG=#{ENV['BERKSHELF_CHEF_CONFIG']}; " \
                if ENV.has_key?('BERKSHELF_CHEF_CONFIG')

            if cookbook.nil?
                cmd += "berks install#{debug_flag} --berksfile=#{berksfile_path}; "
                cmd += "berks upload#{debug_flag} --berksfile=#{berksfile_path} #{upload_options}; "
            else
                cmd += "berks upload#{debug_flag} --berksfile=#{berksfile_path} #{upload_options} #{cookbook}; "
            end

            system(cmd)
        end

        def upload_roles(role = nil)

            if role.nil?
                Dir["#{@repo_path}/roles/*.json"].each do |role_file|
                    upload_role(role_file)
                end
            else
                role_file = "#{@repo_path}/roles/#{role}.json"
                upload_role(role_file) if File.exist?(role_file)
            end
        end

        def get_secret(env_name)

            secretfile = "#{@repo_path}/secrets/#{env_name}"
            if File.exists?(secretfile)
                key = IO.read(secretfile)
            else
                key = SecureRandom.uuid()
                File.open("#{@repo_path}/secrets/#{env_name}", 'w+') { |f| f.write(key) }
            end

            key
        end

        private

        def create_certs(certificates)

            repo_cert_dir = @repo_path + '/.certs'
            FileUtils.mkdir_p(repo_cert_dir)

            if Dir.exist?(certificates)

                raise CertificateError, "Unable to locate public CA certificate for server " +
                    "@#{certificates}/cacert.pem" unless File.exist?("#{certificates}/cacert.pem")

                system("rsync -ru #{certificates}/* #{repo_cert_dir}")
            else

                cacert_file = "#{repo_cert_dir}/cacert.pem"
                cakey_file = "#{repo_cert_dir}/cakey.pem"

                if File.exist?(cacert_file) && File.exist?(cakey_file)

                    ca_cert = OpenSSL::X509::Certificate.new(IO.read(cacert_file))
                    ca_key = OpenSSL::PKey::RSA.new(IO.read(cakey_file))
                else
                    ca_key = OpenSSL::PKey::RSA.new(2048)
                    File.open(cakey_file, 'w+') { |f| f.write(ca_key.to_pem) }

                    ca_subject = "/CN=ca/DC=stackbuilder.org"
                    ca_cert = create_ca_cert(ca_key, ca_subject)
                    File.open(cacert_file, 'w+') { |f| f.write(ca_cert.to_pem) }
                end

                servers = certificates.split(',')
                servers.each do |server|

                    server_dir = "#{repo_cert_dir}/#{server}"
                    server_cert_file = "#{server_dir}/cert.pem"
                    server_key_file = "#{server_dir}/key.pem"

                    unless File.exist?(server_cert_file) && File.exist?(server_key_file)

                        server_key = OpenSSL::PKey::RSA.new(2048)
                        server_subject = "/C=US/O=#{server}/OU=Chef Community/CN=#{server}"
                        server_cert = create_server_cert(create_csr(server_key, server_subject), ca_key, ca_cert)

                        FileUtils.mkdir_p(server_dir)

                        File.open(server_cert_file, 'w+') { |f| f.write(server_cert.to_pem) }
                        File.open(server_key_file, 'w+') { |f| f.write(server_key.to_pem) }
                    end
                end
            end
        end

        def create_ca_cert(ca_key, ca_subject)

            ca_cert = create_cert(ca_key, ca_subject)

            extension_factory = OpenSSL::X509::ExtensionFactory.new
            extension_factory.subject_certificate = ca_cert
            extension_factory.issuer_certificate = ca_cert

            ca_cert.add_extension extension_factory
                .create_extension('subjectKeyIdentifier', 'hash')
            ca_cert.add_extension extension_factory
                .create_extension('basicConstraints', 'CA:TRUE', true)
            ca_cert.add_extension extension_factory
                .create_extension('keyUsage', 'cRLSign,keyCertSign', true)

            ca_cert.sign ca_key, OpenSSL::Digest::SHA256.new

            ca_cert
        end

        def create_csr(key, subject)

            csr = OpenSSL::X509::Request.new
            csr.version = 0
            csr.subject = OpenSSL::X509::Name.parse(subject)
            csr.public_key = key.public_key
            csr.sign key, OpenSSL::Digest::SHA256.new

            csr
        end

        def create_server_cert(csr, ca_key, ca_cert)

            csr_cert = create_cert(csr.public_key, csr.subject, ca_cert.subject)

            extension_factory = OpenSSL::X509::ExtensionFactory.new
            extension_factory.subject_certificate = csr_cert
            extension_factory.issuer_certificate = ca_cert

            csr_cert.add_extension extension_factory
                .create_extension('basicConstraints', 'CA:FALSE')
            csr_cert.add_extension extension_factory
                .create_extension('keyUsage', 'keyEncipherment,dataEncipherment,digitalSignature')
            csr_cert.add_extension extension_factory
                .create_extension('subjectKeyIdentifier', 'hash')

            csr_cert.sign ca_key, OpenSSL::Digest::SHA256.new

            csr_cert
        end

        def create_cert(key, subject, issuer = nil)

            cert = OpenSSL::X509::Certificate.new
            cert.serial = 0x0
            cert.version = 2
            cert.not_before = Time.now
            cert.not_after = Time.now + (10 * 365 * 24 * 60 * 60) # 10 years

            cert.public_key = key.public_key

            cert.subject = subject.is_a?(OpenSSL::X509::Name) ?
                subject : OpenSSL::X509::Name.parse(subject)

            cert.issuer = issuer.is_a?(OpenSSL::X509::Name) ?
                issuer : OpenSSL::X509::Name.parse(issuer.nil? ? subject : issuer)

            cert
        end

        def upload_certificate(server_cert_dir, server_name, server_env_name)

            data_bag_name = 'certificates-' + server_env_name

            data_bag_item = {
                'id' => server_name,
                'cacert' => IO.read(server_cert_dir + "/../cacert.pem"),
                'cert' => IO.read(server_cert_dir + "/cert.pem"),
                'key' => IO.read(server_cert_dir + "/key.pem") }

            tmpfile = "#{Dir.tmpdir}/#{server_name}.json"
            File.open("#{tmpfile}", 'w+') { |f| f.write(data_bag_item.to_json) }

            knife_cmd = Chef::Knife::DataBagFromFile.new
            knife_cmd.name_args = [ data_bag_name, tmpfile ]
            knife_cmd.config[:secret] = get_secret(server_env_name)
            run_knife(knife_cmd)

            puts "Uploaded '#{server_env_name}' certificate for server '#{server_name}' " +
                "to data bag '#{data_bag_name}' at '#{Chef::Config.chef_server_url}'."

        rescue Exception => msg
            @logger.error(msg)
        ensure
            File.delete(tmpfile) unless tmpfile.nil? || !File.exist?(tmpfile)
        end

        def upload_data_bag_items(secret, path, data_bag_name, env_vars)

            tmpfile = nil

            Dir["#{path}/*.json"].each do |data_bag_file|

                data_bag_item = eval_map_values(JSON.load(File.new(data_bag_file, 'r')), env_vars, data_bag_file)

                data_bag_item_name = data_bag_item['id']
                @logger.debug("Uploading data bag '#{data_bag_item_name}' with contents:\n#{data_bag_item.to_yaml}")

                tmpfile = "#{Dir.tmpdir}/#{data_bag_item_name}.json"
                File.open("#{tmpfile}", 'w+') { |f| f.write(data_bag_item.to_json) }

                knife_cmd = Chef::Knife::DataBagFromFile.new
                knife_cmd.name_args = [ data_bag_name, tmpfile ]
                knife_cmd.config[:secret] = secret
                run_knife(knife_cmd)

                File.delete(tmpfile)

                puts "Uploaded item '#{data_bag_item_name}' of data bag " +
                    "'#{data_bag_name}' to '#{Chef::Config.chef_server_url}'."
            end

        rescue Exception => msg
            @logger.error(msg)
        ensure
            File.delete(tmpfile) unless tmpfile.nil? || !File.exist?(tmpfile)
        end

        def upload_role(role_file)

            role_content = eval_map_values(JSON.load(File.new(role_file, 'r')), ENV)

            role_name = role_content.is_a?(Chef::Role) ? role_content.name : role_content['name']
            @logger.debug("Uploading role '#{role_name}' with contents:\n#{role_content.to_yaml}")

            tmpfile = "#{Dir.tmpdir}/#{role_name}.json"
            File.open("#{tmpfile}", 'w+') { |f| f.write(role_content.to_json) }

            knife_cmd = Chef::Knife::RoleFromFile.new
            knife_cmd.name_args = [ tmpfile ]
            run_knife(knife_cmd)

            puts "Uploaded role '#{role_name}' to '#{Chef::Config.chef_server_url}'."

        rescue Exception => msg
            @logger.error(msg)
        ensure
            File.delete(tmpfile) unless tmpfile.nil? || !File.exist?(tmpfile)
        end
    end
end
