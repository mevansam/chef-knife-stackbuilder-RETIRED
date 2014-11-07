# Copyright (c) 2014 Mevan Samaratunga

include StackBuilder::Common::Helpers

module StackBuilder::Stack

    class Stack
        
        attr_reader :id
        attr_reader :name
        attr_reader :nodes
        
        def initialize(provider, stack_file, id = nil, overrides = nil)

            StackBuilder::Common::Config.set_silent
            @logger = StackBuilder::Common::Config.logger

            @provider = provider
            raise InvalidArgs, "Node provider is not derived from
                StackBuilder::Stack::NodeProvider." unless node_task.is_a?(NodeProvider)

            stack = YAML.load_file(stack_file)
            merge_maps(stack, overrides) unless overrides.nil?

            if id.nil?
                @id = SecureRandom.uuid
                @provider.set_stack_id(@id)
            else
                @id = id
                @provider.set_stack_id(@id, false)
            end

            @name = stack["name"]
            @nodes = { }

            if stack.has_key?("stack") && stack["stack"].is_a?(Array)
                
                stack["stack"].each do |n|
                    
                    raise ArgumentError, "Node does not have a 'node' attribute " +
                        "that identifies it: #{n}" unless n.has_key?("node")
                    
                    node_id = n["node"]
                    raise ArgumentError, "Node identified by \"#{node_id}\" " +
                        "already exists." if @nodes.has_key? (node_id)

                    n["attributes"] = { } if n["attributes"].nil?
                    merge_maps(n["attributes"], stack["attributes"]) unless stack["attributes"].nil?

                    node_task = @provider.get_node_task(n)
                    raise InvalidArgs, "Node task is of an invalid type. It is not derived " +
                        "from StackBuilder::Stack::Node." unless node_task.is_a?(NodeTask)

                    @nodes[node_id] = node_task
                end

                # Associate dependencies
                stack["stack"].each do |n|
                    
                    node_task = @nodes[n["node"]]
                    
                    if n.has_key?("depends_on") && n["depends_on"].is_a?(Array)
                        
                        n["depends_on"].each do |d|
                            
                            raise ArgumentError, "Dependency node with name \"#{d}\" " +
                                "is not defined." unless @nodes.has_key?(d)
                            
                            dependent_node_task = @nodes[d]
                            dependent_node_task.parent_nodes << node_task
                            node_task.child_nodes << dependent_node_task
                        end
                    end
                    
                    node_task.validate_target(@nodes)
                end
                
            else
                raise ArgumentError, "System needs to have at least one node defined."
            end
        end

        def orchestrate(events = nil)

            prep_threads = [ ]
            
            execution_list = [ ]
            @nodes.each do |r, n|
                execution_list << n if n.init_dependency_count == 0
                prep_threads += n.prepare(events)
            end
            
            execution_count = 0
            terminate = false
            
            while !terminate && !execution_list.empty? do

                mutex = Mutex.new
                new_execution_list = [ ]
                
                exec_threads = [ ]
                execution_list.each do |n|
                    exec_threads << Thread.new {
                        begin
                            executable_parents = n.orchestrate(events)
                            
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

            raise StackBuilderError, "Processing of system nodes did not " +
                "complete because of errors." if execution_count < @nodes.size
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
                self.orchestrate(Set.new([ "configure" ]))
            else
                self.orchestrate(events)
            end
        end
        
        def reset
            
            @nodes.values.each do |n|
                n.reset
            end
            
            self.orchestrate(Set.new([ "configure" ]))
        end

        def destroy
            
            begin
                destroy_events = Set.new([ "stop", "uninstall" ])
                self.orchestrate(destroy_events)
            rescue Exception => msg
                @logger.warn("An error was encountered attempting to do an orderly tear down of the system: #{msg}")
                @logger.info("All remaining nodes will be destroyed forcefully.")
            end
            
            threads = [ ]
            
            @nodes.values.each do |n|
                n.get_current_scale.times do |i|
                    threads << Thread.new {
        
                        @logger.debug("Deleted #{n} #{i}.")
                        $stdout.printf("Deleting node \"%s\" #%d.\n", n.name, i) unless @logger.debug?
                        
                        n.delete(i)
                    }
                end
            end
            
            threads.each { |t| t.join }
        end
    end

end