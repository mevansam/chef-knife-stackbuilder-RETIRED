# Copyright (c) 2014 Mevan Samaratunga

include StackBuilder::Common::Helpers

module StackBuilder::Stack

    class NodeTask
        
        attr_reader :name

        attr_accessor :scale
        attr_accessor :prev_scale
        
        attr_reader :counter
        attr_reader :parent_nodes
        attr_reader :child_nodes

        attr_reader :resource_sync
        attr_reader :manager
        
        def initialize(manager, nodes, node_config, id)
            
            @logger = StackBuilder::Common::Config.logger

            @manager = manager

            @id = id
            @nodes = nodes
            @parent_nodes = [ ]
            @child_nodes = [ ]
            @counter = 0
            
            @name = node_config['node']
            @attributes = (node_config.has_key?('attributes') ? node_config['attributes'] : { })
            @on_events = (node_config.has_key?('on_events') ? node_config['on_events'] : [ ])

            if node_config.has_key?('targets')

                @logger.warn("Ignoring 'scale' attribute for '#{@name}' as that node has targets.") \
                    if node_config.has_key?("scale")

                @logger.warn("Ignoring 'sync' attribute for '#{@name}' as that node has targets.") \
                    if node_config.has_key?("sync")

                @scale = 0
                @sync = 'no'
            else
                @sync = (node_config.has_key?('sync') ? node_config['sync'] : 'no')
                @scale = (node_config.has_key?("scale") ? node_config["scale"] : 1)

                raise ArgumentError, "The scale for node \"#{@name}\" must be greater than 0." if @scale < 1
            end
            @prev_scale = @scale

            @targets = [ ]

            @node_mutex = Mutex.new
            @resource_sync = [ ]
        end

        def add_dependency(node_name, is_target = false)

            node = @nodes[node_name]

            @targets << node if is_target

            node.parent_nodes << self unless node.parent_nodes.include?(self)
            self.child_nodes << node unless self.child_nodes.include?(node)
        end

        def process_attribute_dependencies

            @attributes.each_value do |v|

                if v =~ /^nodes\[.*\]$/

                    lookup_keys = v.split(/[\[\]]/).reject { |l| l == "nodes" || l.empty? }
                    add_dependency(lookup_keys.shift)
                end
            end
        end

        def init_dependency_count(count = nil)

            if count.nil?
                @counter = child_nodes.size
            else
                @counter += count
            end

            @counter
        end
        
        def dec_dependency_count
            @node_mutex.synchronize {
                @counter -= 1
                return @counter
            }
        end
        
        def prepare

            threads = [ ]

            if @targets.empty?

                # You need to prepare nodes only if this node task
                # is the target. i.e. no referenced targets

                current_scale = @manager.get_scale
                if current_scale > @scale

                    @logger.debug("Scaling #{self} from #{current_scale} down to #{@scale}")

                    # Scale Down

                    delete_events = Set.new([ "stop", "uninstall" ])
                    @scale.step(current_scale - 1).to_a.each do |i|

                        resource_sync = @resource_sync[i]
                        resource_sync.wait

                        threads << Thread.new {

                            begin
                                @logger.debug("Deleting #{self} #{i}.")
                                $stdout.printf("Deleting node resource '%s[#%d]'.\n",
                                    @name, i) unless @logger.debug?

                                @manager.process(i, delete_events, parse_attributes(@attributes, i))
                                @manager.delete(i)

                            rescue Exception => msg

                                puts("Fatal Error: #{msg}")
                                @logger.debug(msg.backtrace.join("\n\t"))

                                raise StackBuilder::Common::StackDeleteError,
                                    "Deleting node resource '#{name}[#{i}]' " +
                                    "terminated with an error: #{msg}"
                            ensure
                                resource_sync.signal
                            end
                        }
                    end

                    (current_scale - 1).downto(@scale) do |i|
                        @resource_sync.delete_at(i)
                    end
                end

                if @scale > current_scale

                    @logger.debug("Scaling #{self} from #{current_scale} up to #{@scale}")

                    # Scale up

                    current_scale.step(@scale - 1) do |i|

                        sync = StackBuilder::Common::Semaphore.new
                        @resource_sync[i] = sync

                        threads << Thread.new {

                            begin
                                @logger.debug("Creating #{self} #{i}.")
                                $stdout.printf( "Creating node resource '%s[#%d]'.\n",
                                    @name, i) unless @logger.debug?

                                @manager.create(i)

                            rescue Exception => msg

                                puts("Fatal Error: #{msg}")
                                @logger.debug(msg.backtrace.join("\n\t"))

                                raise StackBuilder::Common::StackCreateError,
                                    "Creating node resource '#{name}[#{i}]' " +
                                    "terminated with an error: #{msg}"
                            ensure
                                @resource_sync[i].signal
                            end
                        }
                    end
                end

                @prev_scale = current_scale
                @manager.set_scale(@scale)
            end

            threads
        end

        def orchestrate(events)

            threads = [ ]

            scale = @scale
            if scale > 0

                if @sync == "first"
                    @manager.process(scale, events, self.parse_attributes(@attributes, 0))
                    scale -= 1
                end

                if @sync == "all"
                    scale.times do |i|
                        @manager.process(i, events, self.parse_attributes(@attributes, i))
                    end
                else
                    scale.times do |i|
                        spawn_processing(i, events, threads)
                    end
                end

            elsif !@targets.empty?

                @targets.each do |t|
                    t.manager.get_scale.times do |i|
                        spawn_processing(i, events, threads, t)
                    end
                end
            end

            threads.each { |t| t.join }

            executable_parents = [ ]
            parent_nodes.each do |p|
                executable_parents << p if p.dec_dependency_count == 0
            end
            executable_parents
        end

        def to_s
            p = "Parent_Nodes[#{@parent_nodes.collect { |n| "#{n.name}:#{n.counter}" }.join(", ")}]"
            c = "Child_Nodes[#{@child_nodes.collect { |n| n.name }.join(", ")}]"
            
            "(#{@name}, #{@sync}, #{p}, #{c})"
        end

        private

        def spawn_processing(i, events, threads, target = nil)

            if target.nil?
                resource_sync[i].wait

                target_manager = nil
                prev_scale = @prev_scale
            else
                target.resource_sync[i].wait

                target_manager = target.manager
                prev_scale = target.prev_scale
            end

            threads << Thread.new {

                begin
                    @logger.debug("Processing #{self} VM ##{i}#{events.nil? ? "" : " with events \"" + events.collect { |e| e }.join(",") + "\""}.")
                    if target_manager.nil?

                        $stdout.printf( "Processing node '%s[%d]'.\n",
                            @name, i) unless @logger.debug?
                    else
                        $stdout.printf( "Processing target node '%s[%d]' from %s.\n",
                            target_manager.name, i, @name) unless @logger.debug?
                    end

                    if events.nil?
                        # Always run default events for node building. The idempotent nature of Chef
                        # should ensure that if the VM is consistent then the recipe will be a noop
                        orchestrate_events = Set.new([ "create", "install", "configure" ])
                        @logger.debug("Events for node VM #{name} / #{i} build: #{orchestrate_events.collect { |e| e }.join(", ")}")
                    else
                        # If no scale up occurs then run chef roles only for the given event.
                        orchestrate_events = events.clone
                        # If new VMs have been added to the cluster to scale up then add default events for the new VM.
                        if i >= prev_scale
                            orchestrate_events = orchestrate_events.merge([ "create", "install", "configure" ])
                            @logger.debug("Events for node VM #{name} / #{i} build: #{orchestrate_events.collect { |e| e }.join(", ")}")
                        end
                    end

                    @manager.process(i, orchestrate_events, parse_attributes(@attributes, i), target_manager)

                rescue Exception => msg

                    puts("Fatal Error: #{msg}")
                    @logger.debug(msg.backtrace.join("\n\t"))

                    raise StackBuilder::Common::StackOrchestrateError,
                        "Orchestrating node resource '#{name}[#{i}]' " +
                        "terminated with an error: #{msg}"
                ensure
                    if target.nil?
                        resource_sync[i].signal
                    else
                        target.resource_sync[i].signal
                    end
                end
            }
        end

        def parse_attributes(attributes, index)

            results = { }
            attributes.each_pair do |k, v|

                @logger.debug("Evaluating #{k} = #{v}")

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
                    unless node.nil?

                        node_attributes = node.manager.node_attributes
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

                @logger.debug("Evaluated #{k} = #{results[k]}")
            end

            results
        end

    end
    
end