# Copyright (c) 2014 Mevan Samaratunga

module StackBuilder::Common

    module Helpers

        #
        # Returns whether platform is a nix OS
        #
        def is_nix_os?
            RbConfig::CONFIG["host_os"] =~ /linux|freebsd|darwin|unix/
        end

        # Return whether platform is a OS X
        def is_os_x?
            RbConfig::CONFIG["host_os"] =~ /darwin/
        end
        
        #
        # Runs the given execution list asynchronously if fork is supported
        #
        def run_jobs(jobs, wait = true, echo = false)

            jobs = [ jobs ] unless jobs.is_a?(Array)
            job_handles = { }

            if is_nix_os?

                jobs.each do |job|

                    read, write = IO.pipe

                    pid = fork {

                        read.close

                        if echo
                            stdout = StackBuilder::Common::TeeIO.new($stdout)
                            stderr = StackBuilder::Common::TeeIO.new($stderr)
                        else
                            stdout = StringIO.new
                            stderr = StringIO.new
                        end

                        begin
                            previous_stdout, $stdout = $stdout, stdout
                            previous_stderr, $stderr = $stderr, stderr
                            yield(job)
                            Marshal.dump([stdout.string, stderr.string], write)
                        ensure
                            $stdout = previous_stdout
                            $stderr = previous_stderr
                        end
                    }
                    write.close

                    job_handles[job.object_id] = [ pid, read ]
                end
            end

            if wait
                wait_jobs(job_handles)
            else
                job_handles
            end
        end

        #
        # This should be called after run_jobs() with the returned handles
        # if you want to wait for the forked jobs to complete and retrieve
        # the results.
        #
        def wait_jobs(job_handles)

            job_results = { }
            job_handles.each do |job_id, handle|

                result = Marshal.load(handle[1])
                Process.waitpid(handle[0])
                job_results[job_id] = result
            end

            job_results
        end

        #
        # Loads a Yaml file and resolves any includes
        #
        def load_yaml(file, env_vars, my = nil)

            yaml = YAML.load_file(file)
            eval_map_values(yaml, env_vars, file, my)
        end

        #
        # Evaluates map values against the
        # given map of environment variables
        #
        def eval_map_values(v, env, file = nil, my = nil)

            my ||= v

            if v.is_a?(String)

                if v=~/#\{.*\}/
                    begin
                        return eval("\"#{v.gsub(/\"/, "\\\"")}\"")

                    rescue Exception => msg

                        StackBuilder::Common::Config.logger.debug( "Error evaluating configuration " +
                            "variable '#{v}': #{msg}\nenv = #{env}\nmy = #{my}")

                        return v
                    end

                elsif v.start_with?('<<')

                    k1 = v[/<<(\w*)[\*\$\+]/,1]
                    env_val = k1.nil? || k1.empty? ? nil : ENV[k1]

                    i = k1.length + 3
                    k2 = v[i,v.length-i]

                    case v[i-1]

                        when '*'
                            if env_val.nil?
                                v = ask(k2) { |q| q.echo = "*" }.to_s
                                ENV[k1] = v unless k1.nil? || k1.empty?
                            else
                                v = env_val
                            end
                            return v

                        when '$'
                            if env_val.nil?
                                v = ask(k2).to_s
                                ENV[k1] = v unless k1.nil? || k1.empty?
                            else
                                v = env_val
                            end
                            return v

                        when '+'
                            lookup_keys = (env_val || k2).split(/[\[\]]/).reject { |k| k.empty? }

                            key = lookup_keys.shift
                            include_file = key.start_with?('/') || key.nil? ? key : File.expand_path('../' + key, file)

                            begin
                                yaml = load_yaml(include_file, env, my)

                                return lookup_keys.empty? ? yaml
                                    : eval('yaml' + lookup_keys.collect { |v| "['#{v}']" }.join)

                            rescue Exception => msg
                                puts "ERROR: Unable to include referenced data '#{v}'."
                                raise msg
                            end
                        else
                            return v
                    end
                end

            elsif v.is_a?(Hash)

                new_keys = { }
                v.each_pair do |k,vv|

                    if k=~/#\{.*\}/

                        new_k = eval("\"#{k}\"")
                        if k!=new_k
                            v.delete(k)
                            new_keys[new_k] = eval_map_values(vv, env, file, my)
                            next
                        end
                    end

                    v[k] = eval_map_values(vv, env, file, my)
                end
                v.merge!(new_keys) unless new_keys.empty?

            elsif v.is_a?(Array)
                v.map! { |vv| eval_map_values(vv, env, file, my) }
            end

            v
        end

        # 
        # Merges values of keys of to maps
        #        
        def merge_maps(map1, map2)
            
            map2.each_pair do |k, v2|
                
                v1 = map1[k]
                if v1.nil? 
                    if v2.is_a?(Hash)
                        v1 = { }
                        merge_maps(v1, v2)
                    elsif v2.is_a?(Array)
                        v1 = [ ] + v2
                    else
                        v1 = v2
                    end
                    map1[k] = v1
                elsif v1.is_a?(Hash) && v2.is_a?(Hash)
                    merge_maps(v1, v2)
                elsif v1.is_a?(Array) && v2.is_a?(Array)
                    
                    if v2.size > 0
                    
                        if v1.size > 0 && v1[0].is_a?(Hash) && v2[0].is_a?(Hash)
                            
                            i = 0
                            while i < [ v1.size, v2.size ].max do
                                
                                v1[i] = { } if v1[i].nil?
                                v2[i] = { } if v2[i].nil?
                                merge_maps(v1[i], v2[i])
                                
                                i += 1
                            end
                        
                        else
                            v1 += v2
                        end
                    end
                else
                    map1[k] = v2
                end 
            end
        end

        #
        # Prints a 2-d array within a table formatted to terminal size
        #
        def print_table(table, format = true, cols = nil)
            
            # Apply column filter
            unless cols.nil?
                
                headings = cols.split(",").to_set
                
                cols_to_delete = [ ]
                i = 0
                table[0].each do |col|
                    cols_to_delete << i unless headings.include?(col)
                    i = i + 1
                end
                
                table.each do |row|
                    cols_to_delete.reverse_each { |j| row.delete_at(j) }
                end
            end
            
            if format
                
                # Calculate widths
                widths = []
                table.each do |line|
                    c = 0
                    line.each do |col|
                        
                        len = col.nil? ? 0 : col.length
                        widths[c] = (widths[c] && widths[c] > len) ? widths[c] : len
                        c += 1
                    end
                end
                
                max_scr_cols = HighLine::SystemExtensions.terminal_size[0].nil? ? 9999 
                    : HighLine::SystemExtensions.terminal_size[0] - (widths.length * 3) - 2
                    
                max_tbl_cols = 0
                width_map = {}
                
                c = 0
                widths.each do |n| 
                    max_tbl_cols += n
                    width_map[c] = n
                    c += 1
                end
                c = nil
    
                # Shrink columns that have too much space to try and fit table into visible console
                if max_tbl_cols > max_scr_cols
                    
                    width_map = width_map.sort_by { |col,width| -width }
                    
                    last_col = widths.length - 1
                    c = 0
                    
                    while max_tbl_cols > max_scr_cols && c < last_col
                        
                        while width_map[c][1] > width_map[c + 1][1]
                            
                            i = c
                            while i >= 0
                                width_map[i][1] -= 1
                                widths[width_map[i][0]] -= 1
                                max_tbl_cols -= 1
                                i -= 1
                                
                                break if max_tbl_cols == max_scr_cols
                            end
                            break if max_tbl_cols == max_scr_cols
                        end
                        c += 1
                    end
                end
                
                border1 = ""
                border2 = ""
                format = ""
                widths.each do |n|
                    
                    border1 += "+#{'-' * (n + 2)}"
                    border2 += "+#{'=' * (n + 2)}"
                    format += "| %#{n}s "
                end
                border1 += "+\n"
                border2 += "+\n"
                format += "|\n"
                
            else
                c = nil
                border1 = nil
                border2 = nil
                
                format = Array.new(table[0].size, "%s,").join.chop! + "\n"
                
                # Delete column headings for unformatted output
                table.delete_at(0)
            end
            
            # Print each line.
            write_header_border = !border2.nil?
            printf border1 if border1
            table.each do |line|
                
                if c
                    # Check if cell needs to be truncated
                    i = 0
                    while i < c
                        
                        j = width_map[i][0]
                        width = width_map[i][1]
                        
                        cell = line[j]
                        len = cell.length
                        if len > width
                            line[j] = cell[0, width - 2] + ".."
                        end
                        i += 1
                    end
                end
                
                printf format, *line
                if write_header_border
                    printf border2
                    write_header_border = false
                end
            end
            printf border1 if border1

        end

        #
        # Helper command to run Chef knife
        #
        def run_knife(knife_cmd, retries = 0, output = StringIO.new, error = StringIO.new)

            knife_cmd.ui = Chef::Knife::UI.new(output, error, STDIN, knife_cmd.config) \
                unless output.nil? && error.nil?

            run = true
            while run

                begin
                    knife_cmd.run
                    run = false

                rescue Exception => msg

                    if retries==0

                        if @logger.level>=::Logger::WARN
                            puts "Knife execution failed with an error."
                            puts "* StdOut from knife run: #{output.string}"
                            puts "* StdErr from knife run: #{error.string}"
                        end

                        @logger.debug(msg.backtrace.join("\n\t")) if Config.logger.debug?
                        raise msg
                    end

                    @logger.debug("Knife command #{knife_cmd} failed. Retrying after 2s.")

                    sleep 2
                    retries -= 1
                end
            end

            output.string
        end

        #
        # Captures standard out and error to a string
        #
        def capture_stdout
            # The output stream must be an IO-like object. In this case we capture it in
            # an in-memory IO object so we can return the string value. You can assign any
            # IO object here.
            stdout = StringIO.new
            previous_stdout, $stdout = $stdout, stdout
            previous_stderr, $stderr = $stderr, stdout
            yield
            stdout.string
            
        rescue Exception => msg
            puts("Error: #{stdout.string}")
            raise msg
            
        ensure
            # Restore the previous value of stderr (typically equal to STDERR).
            $stdout = previous_stdout
            $stderr = previous_stderr
        end

        # Creates and ssh session to the given host using the given credentials
        def ssh_create(host, user, key)

            if key.start_with?('-----BEGIN RSA PRIVATE KEY-----')
                ssh = Net::SSH.start(host, user,
                    {
                        :key_data => key,
                        :user_known_hosts_file => "/dev/null"
                    } )
            elsif File.exist?(key)
                ssh = Net::SSH.start(host, user,
                    {
                        :key_data => IO.read(key),
                        :user_known_hosts_file => "/dev/null"
                    } )
            else
                ssh = Net::SSH.start(host, user,
                    {
                        :password => key,
                        :user_known_hosts_file => "/dev/null"
                    } )
            end

            ssh
        end

        # Executes a remote shell command and returns exit status
        def ssh_exec!(ssh, command)

            stdout_data = ""
            stderr_data = ""
            exit_code = nil
            exit_signal = nil

            ssh.open_channel do |channel|
                channel.exec(command) do |ch, success|
                    unless success
                        abort "FAILED: couldn't execute command (ssh.channel.exec)"
                    end
                    channel.on_data do |ch,data|
                        stdout_data+=data
                    end

                    channel.on_extended_data do |ch,type,data|
                        stderr_data+=data
                    end

                    channel.on_request("exit-status") do |ch,data|
                        exit_code = data.read_long
                    end

                    channel.on_request("exit-signal") do |ch, data|
                        exit_signal = data.read_long
                    end
                end
            end
            ssh.loop

            {
                :out => stdout_data,
                :err => stderr_data,
                :exit_code => exit_code,
                :exit_signal => exit_signal
            }
        end

    end
end
