# Copyright (c) 2014 Mevan Samaratunga

include StackBuilder::Common::Helpers

module Knife::StackBuilder::Stack

    class Stack
        
        attr_reader :id
        attr_reader :name
        attr_reader :nodes
        
        def initialize(connection, system_pattern, id = nil, overrides = nil)

            Knife::StackBuilder::Config.set_silent
            @logger = Knife::StackBuilder::Config.logger
            
            cookbook_repo_path = File.dirname(File.expand_path(system_pattern));

            system = YAML.load_file(system_pattern)
            merge_maps(system, overrides) unless overrides.nil?
            
            system_vms = nil
            if !id.nil?
                
                # Retrieve any VMs that are part of the given system ID
                properties = { }
                properties["name"] = "^(?!__Deleted__)"
                properties["description"] = "; ID: #{id}"
                system_vms = Click2Compute::API::VM::find(connection, properties, false)
                # system_vms = Click2Compute::API::VM::find(connection, properties)
                
                cloud_error("No VMs found for system ID #{id}.") if system_vms.empty?
                
                @id = id
            else
                @id = SecureRandom.uuid
            end
            
            @connection = connection
            
            @name = system["name"]
            @has_firecall_ticket = system.has_key?("firecall_ticket")
            
            @nodes = { }
            
            if system.has_key?("nodes") &&
                system["nodes"].is_a?(Array)
                
                system["nodes"].each do |n|
                    
                    raise ArgumentError, "Node does not have a name: #{n}" unless n.has_key?("name")
                    
                    r = n["name"]
                    raise ArgumentError, "Node with name \"#{r}\" already exists." if @nodes.has_key?(r)
                    
                    vms = [ ]
                    unless system_vms.nil?

                        system_vms.each do |vm|
                            if vm.name == r
                                server_index = vm.info["description"][/; Index: \d+/]
                                unless server_index.nil?
                                    vms[server_index[/\d+/].to_i] = vm
                                else
                                    cloud_error( "A system node has a description without a valid server " \
                                        "index value: vm = #{vm}}; description = #{vm.info["description"]}" )
                                end
                            end
                        end
                    end
                    
                    if n.has_key?("vm")
                        @nodes[r] = Knife::StackBuilder::VMNode.new(n, system, @id, @nodes, cookbook_repo_path, vms)
                    elsif n.has_key?("target_vm")
                        @nodes[r] = Knife::StackBuilder::ChefNode.new(n, system, @id, @nodes, cookbook_repo_path, vms)
                    else
                        @logger.debug("Creating generic no-op node: #{n}")
                        @nodes[r] = Knife::StackBuilder::Node.new(n, system, @id, @nodes)
                    end
                    
                end
                
                system["nodes"].each do |n|
                    
                    node = @nodes[n["name"]] 
                    
                    if n.has_key?("depends_on") &&
                        n["depends_on"].is_a?(Array)
                        
                        n["depends_on"].each do |d|
                            
                            raise ArgumentError, "Dependency node with name \"#{d}\" is not defined." unless @nodes.has_key?(d)
                            
                            dependent_node = @nodes[d]
                            
                            dependent_node.parent_nodes << node
                            node.child_nodes << dependent_node
                        end
                    end
                    
                    node.validate_target()
                end
                
            else
                raise ArgumentError, "System needs to have at least one node defined."
            end
        end
        
        def validate
            self.orchestrate(nil, nil)
        end
        
        def orchestrate(connection = @connection, events = nil)
            
            if !connection.nil?
                connection.validate_ssh_login() if !@has_firecall_ticket
            end
            
            prep_threads = [ ]
            
            execution_list = [ ]
            @nodes.each do |r, n|
                execution_list << n if n.init_dependency_count == 0
                prep_threads += n.prepare(connection, events) unless connection.nil?
            end
            
            execution_count = 0
            terminate = false
            
            while !terminate && !execution_list.empty? do
                
                @logger.debug("#{connection.nil? ? "Validating" : "Orchestrating"} => \n\t#{execution_list.collect { |n| n }.join("\n\t")}")
                
                mutex = Mutex.new
                new_execution_list = [ ]
                
                exec_threads = [ ]
                execution_list.each do |n|
                    exec_threads << Thread.new {
                        begin
                            executable_parents = n.orchestrate(connection, events)
                            
                            mutex.synchronize {
                                new_execution_list |= executable_parents
                                execution_count += 1
                            }                    
                        rescue Exception => msg
                            @logger.error("Orchestrating node '#{n}' terminated with an exception: #{msg}")
                            @logger.debug(msg.backtrace.join("\n\t"))
                            terminate = true
                        end
                    }
                end
                exec_threads.each { |t| t.join }

                execution_list = new_execution_list
            end
            
            prep_threads.each { |t| t.join }
            
            if connection.nil?
                
                cloud_error( "All the nodes were not processed. This could" \
                    " be due to a circular dependency." ) if execution_count < @nodes.size
                
                @logger.debug("All dependencies passed validation.") if @logger.debug?
                
            elsif execution_count < @nodes.size
                
                cloud_error("Processing of system nodes did not complete because of errors.")
            end
        end
        
        def status
        end
        
        def scale(name, scale, events = nil)
            
            node = @nodes[name]
            
            cloud_error("Invalid node name \"#{name}'\".") if node.nil?
            raise ArgumentError, "The scale for node \"#{@name}\" must be greater than 0." if scale < 1
            
            @logger.debug( "Increasing scale for '#{node}' to '#{scale}' which currently has a " \
                "default scale of #{node.scale} and actual scale of #{node.get_current_scale}.")
            
            node.scale = scale
            node.reset
            
            if events.nil?
                self.orchestrate(@connection, Set.new([ "configure" ]))
            else
                self.orchestrate(@connection, events)
            end
        end
        
        def reset
            
            @nodes.values.each do |n|
                n.reset
            end
            
            self.orchestrate(@connection, Set.new([ "configure" ]))
        end

        def destroy
            
            begin
                destroy_events = Set.new([ "stop", "uninstall" ])
                self.orchestrate(@connection, destroy_events)
            rescue Exception => msg
                @logger.warn("An error was encountered attempting to do an orderly tear down of the system: #{msg}")
                @logger.info("All remaining nodes will be destroyed forcefully.")
            end
            
            threads = [ ]
            
            @nodes.values.each do |n|
                n.get_current_scale().times do |i|
                    threads << Thread.new {
        
                        @logger.debug("Deleted #{n} #{i}.")
                        $stdout.printf("Deleting node \"%s\" #%d.\n", n.name, i) unless @logger.debug?
                        
                        n.delete(@connection, i)
                    }
                end
            end
            
            threads.each { |t| t.join }
        end
    end

end