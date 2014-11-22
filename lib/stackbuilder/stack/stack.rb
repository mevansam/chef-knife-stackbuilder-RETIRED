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

            raise InvalidArgs, "Node provider is not derived from
                StackBuilder::Stack::NodeProvider." unless provider.is_a?(NodeProvider)

            @provider = provider
            env_vars = provider.get_env_vars

            stack = StackBuilder::Common.load_yaml(stack_file, env_vars)
            @logger.debug("Initializing stack definition:\n #{stack.to_yaml}")

            overrides = JSON.load(File.new(overrides, 'r')) unless overrides.nil? || !overrides.end_with?('.json')
            merge_maps(stack, overrides) unless overrides.nil?

            if id.nil?
                @id = SecureRandom.uuid.gsub(/-/, '')
                @provider.set_stack(stack, @id)
            else
                @id = id
                @provider.set_stack(stack, @id)
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

                    node_manager = @provider.get_node_manager(n)
                    raise InvalidArgs, "Node task is of an invalid type. It is not derived " +
                        "from StackBuilder::Stack::Node." unless node_manager.is_a?(NodeManager)

                    @nodes[node_id] = NodeTask.new(node_manager, @nodes, n, id)
                end

                # Associate dependencies
                stack["stack"].each do |n|
                    
                    node_task = @nodes[n["node"]]
                    
                    if n.has_key?("depends_on") && n["depends_on"].is_a?(Array)
                        
                        n["depends_on"].each do |d|
                            
                            raise ArgumentError, "Dependency node \"#{d}\" " +
                                "is not defined." unless @nodes.has_key?(d)
                            
                            node_task.add_dependency(d)
                        end
                    end

                    if n.has_key?("targets") && n["targets"].is_a?(Array)

                        n["targets"].each do |d|

                            raise ArgumentError, "Target node \"#{d}\" " +
                                "is not defined." unless @nodes.has_key?(d)

                            node_task.add_dependency(d, true)
                        end
                    end

                    node_task.process_attribute_dependencies
                end
                
            else
                raise ArgumentError, "System needs to have at least one node defined."
            end
        end

        def orchestrate(events = nil, name = nil, scale = nil)

            events = Set.new([ "configure" ]) if events.nil?

            unless name.nil?
                node = @nodes[name]
                raise StackBuilder::Common::StackBuilderError, "Invalid node name \"#{name}'\"." if node.nil?

                unless scale.nil?
                    raise ArgumentError, "The scale for node \"#{@name}\" must be greater than 0." if scale < 1
                    node.scale = scale
                end
            end

            prep_threads = [ ]
            execution_list = [ ]

            if name.nil?

                @nodes.each_value do |n|
                    execution_list << n if n.init_dependency_count == 0
                    prep_threads += n.prepare
                end

                task_count = @nodes.size
            else
                # Only process nodes that depend on 'name' and their dependencies

                def add_parent_task(node, prep_threads, nodes_visited)

                    prep_threads += node.prepare
                    nodes_visited << node.name

                    node.init_dependency_count(1)

                    node.parent_nodes.each do |n|
                        add_parent_task(n, prep_threads, nodes_visited)
                    end
                end

                node = @nodes[name]
                nodes_visited = Set.new([ node.name ])

                execution_list << node
                prep_threads += node.prepare

                node.parent_nodes.each do |n|
                    add_parent_task(n, prep_threads, nodes_visited)
                end

                task_count = nodes_visited.size
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
                            @logger.info(msg.backtrace.join("\n\t"))
                            terminate = true
                        end
                    }
                end
                exec_threads.each { |t| t.join }

                execution_list = new_execution_list
            end
            
            prep_threads.each { |t| t.join }

            @nodes.each_value do |n|
                n.prev_scale = n.scale
            end

            raise StackBuilder::Common::StackBuilderError, "Processing of stack nodes " +
                "did not complete because of errors." if execution_count < task_count
        end

        def scale(name, scale)
            self.orchestrate(nil, name, scale)
        end

        def destroy

            @nodes.values.each { |n| n.deleted = true }
            
            begin
                destroy_events = Set.new([ "stop", "uninstall" ])
                self.orchestrate(destroy_events)
            rescue Exception => msg
                @logger.warn("An error was encountered attempting to do an orderly tear down of the system: #{msg}")
                @logger.info("All remaining nodes will be destroyed forcefully.")
            end
            
            threads = [ ]
            
            @nodes.values.each do |n|
                (n.manager.get_scale - 1).downto(0) do |i|
                    threads << Thread.new {
        
                        @logger.debug("Deleted #{n} #{i}.")
                        $stdout.printf("Deleting node \"%s\" #%d.\n", n.name, i) unless @logger.debug?
                        
                        n.manager.delete(i)
                    }
                end
            end
            
            threads.each { |t| t.join }
        end
    end

end