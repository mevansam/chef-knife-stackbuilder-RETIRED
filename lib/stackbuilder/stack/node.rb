# Copyright (c) 2014 Mevan Samaratunga

include StackBuilder::Common::Helpers

module StackBuilder::Stack

    class Node
        
        attr_reader :name
        attr_accessor :scale
        
        attr_reader :counter
        attr_reader :parent_nodes
        attr_reader :child_nodes
        
        def initialize(node_config, system_config, id, nodes)
            
            @@logger ||= StackBuilder::Config.logger
            @cookbook_repo_path ||= nil
            
            @id ||= id
            @nodes ||= nodes
            @parent_nodes = [ ]
            @child_nodes = [ ]
            @counter = 0
            
            @name = node_config["name"]
            @firecall_ticket = system_config["firecall_ticket"] if system_config.has_key?("firecall_ticket")
            @on_events = (node_config.has_key?("on_events") ? node_config["on_events"] : [ ])
            
            @sync = (node_config.has_key?("sync") ? node_config["sync"] : "no")
            @scale = (node_config.has_key?("scale") ? node_config["scale"] : 1)
            
            raise ArgumentError, "The scale for node \"#{@name}\" must be greater than 0." if @scale < 1

            @attributes = { }
            merge_maps(@attributes, node_config["attributes"]) if node_config.has_key?("attributes") && !node_config["attributes"].nil?
            merge_maps(@attributes, system_config["attributes"]) if system_config.has_key?("attributes") && !system_config["attributes"].nil?

            @reset = false            
            @target = nil
            
            @node_mutex = Mutex.new
        end
        
        def reset
            @reset = true
        end
        
        def validate_target
            
            unless @target.nil?
                
                if @nodes.has_key?(@target)
                    
                    # replace target name with actual node object
                    @target = @nodes[@target]
                    
                    @target.parent_nodes << self
                    self.child_nodes << @target
                else
                    @@logger.warn("Target node with name \"#{@target}\" was not " \
                        "found for node: #{self}.") unless @nodes.has_key?(@target)
                end
            end
        end
        
        def get_current_scale
            return @scale
        end
        
        def update_scale(scale)
            @scale = scale
        end
        
        def get_resource_sync(index)
            return nil
        end
        
        def get_resource(index)
            return nil
        end
        
        def get_node_attributes
            return [ ]
        end
        
        def parse_attributes(attributes, index)
            
            results = { }
            attributes.each_pair do |k, v|
                
                @@logger.debug("Evaluating #{k} = #{v}")
                
                if v.is_a?(Hash)
                    results[k] = parse_attributes(v, index)
                    
                elsif v.is_a?(Array)
                    
                    results[k] = [ ]
                    v.each do |aval|
                        results[k] << parse_attributes( { "#" => aval }, index)["#"]
                    end
                    
                elsif v =~ /^nodes\[.*\]$/

                    lookup_keys = v.split(/[\[\]]/).reject { |l| l == "nodes" || l.empty? }
                    
                    l = lookup_keys.shift
                    node = @nodes[l]
                    if !node.nil?
                        
                        node_attributes = node.get_node_attributes()
                        unless node_attributes.nil? || node_attributes.empty?
                            
                            indexes = [ ]
                            
                            l = lookup_keys.shift
                            case l
                                when "*"
                                    indexes = (0..node.scale-1).to_a
                                when /\d+/
                                    indexes << l.to_i
                                else
                                    indexes << 0
                            end
                            
                            values = [ ]
                            indexes.each do |i|
                                v = node_attributes[i]
                                lookup_keys.each do |j|
                                    v = v[j]
                                    break if v.nil?
                                end
                                values << v
                            end
                            
                            results[k] = (l == "*" ? values : values[0])
                        end
                    end
                    
                elsif v.is_a?(String)
                    v = v.split(/(\#){|}/)
                    
                    if v.size == 1
                        results[k] = v[0]
                    else
                        results[k] = ""
                        
                        is_var = false
                        v.each do |s|
                            
                            if is_var
                                is_var = false
                                sstr = (s == "index" ? index.to_s : parse_attributes( { "#" => s }, index)["#"])
                                results[k] << sstr unless sstr.nil?
                                next
                            end
                            
                            if s == "#"
                                is_var = true
                                next
                            end
                                
                            results[k] << s
                        end
                    end
                else
                    results[k] = v
                end
                
                @@logger.debug("Evaluated #{k} = #{results[k]}")
            end
            
            return results
        end
                
        def init_dependency_count
            @counter = child_nodes.size
            return @counter
        end
        
        def dec_dependency_count
            @node_mutex.synchronize {
                @counter -= 1
                return @counter
            }
        end
        
        def prepare(connection, events)
            
            threads = [ ]
            
            if @target.nil?

                current_scale = self.get_current_scale()
                if current_scale > @scale
                    
                    if @reset
                        
                        # Scale Down
                         
                        delete_events = Set.new([ "stop", "uninstall" ])
                        @scale.step(current_scale - 1).to_a.each do |i|
                            threads << Thread.new {
                                
                                begin
                                    @@logger.debug("Deleting #{self} #{i}.")
                                    $stdout.printf("Deleting node \"%s\" #%d.\n", @name, i) unless @@logger.debug?
                                    
                                    self.process(connection, i, delete_events)
                                    self.delete(connection, i)
                                    
                                rescue Exception => msg
                                    
                                    puts("Fatal Error: #{msg}")
                                    @@logger.debug(msg.backtrace.join("\n\t"))
                                    cloud_error("Deleting VM #{name} / #{i} terminated with an error: #{msg}") 
                                end
                            }
                        end
                    else
                        @scale = current_scale
                    end
                end
                
                if events.nil? || !events.include?("uninstall")
                    @@logger.debug("Updating scale for #{self} as #{@scale}")
                    
                    self.update_scale(@scale)
                    @scale.times do |i|
                        threads << Thread.new {
                            self.create(connection, i)
                        }
                    end
                end
            end
            
            return threads
        end

        def orchestrate(connection, events)
            
            unless connection.nil?
                
                scale = (@target.nil? ? @scale : @target.scale)
                if scale > 0
                    
                    threads = [ ]
                    
                    if @sync == "first"
                        self.process(connection, scale, events)
                        scale -= 1
                    end
                    
                    if @sync == "all"
                        scale.times do |i|
                            self.process(connection, i, events)
                        end
                    else
                        scale.times do |i|
                            threads << Thread.new {
                                
                                @@logger.debug("Processing #{self} VM ##{i}#{events.nil? ? "" : " with events \"" + events.collect { |e| e }.join(",") + "\""}.")
                                $stdout.printf("Processing node \"%s\" #%d.\n", @name, i) unless @@logger.debug?

                                if events.nil?
                                    # Always run default events for node building. The idempotent nature of Chef
                                    # should ensure that if the VM is consistent then the recipe will be a noop
                                    orchestrate_events = Set.new([ "create", "install", "configure", "start" ])
                                    @@logger.debug("Events for node VM #{name} / #{i} build: #{orchestrate_events.collect { |e| e }.join(", ")}")
                                else
                                    # If no scale up occurs then run chef roles only for the given event.
                                    orchestrate_events = events.clone
                                    # If new VMs have been added to the cluster to scale up then add default events for the new VM.
                                    if self.get_node_attributes[i].nil?
                                        orchestrate_events = orchestrate_events.merge([ "create", "install", "configure", "start" ])
                                        @@logger.debug("Events for node VM #{name} / #{i} build: #{orchestrate_events.collect { |e| e }.join(", ")}")
                                    end
                                end
                                
                                self.process(connection, i, orchestrate_events)
                            }
                        end
                    end
                    
                    threads.each { |t| t.join }
                end
            else
                @@logger.debug("Validating #{self}...")
            end
            
            executable_parents = [ ]
            parent_nodes.each do |p|
                executable_parents << p if p.dec_dependency_count == 0
            end
            return executable_parents
        end
        
        def create(connection, index)
        end
        
        def process(connection, index, events)
        end
        
        def delete(connection, index)
        end
        
        def to_s
            t = (@target.nil? ? "" : ", target[ #{@target} ]")
            p = "Parent_Nodes[#{@parent_nodes.collect { |n| "#{n.name},#{n.counter}" }.join(", ")}]"
            c = "Child_Nodes[#{@child_nodes.collect { |n| n.name }.join(", ")}]"
            
            "(#{@name}, #{@sync}#{t}, #{p}, #{c})"
        end
        
    end
    
end