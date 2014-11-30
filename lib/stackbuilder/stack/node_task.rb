# Copyright (c) 2014 Mevan Samaratunga

include StackBuilder::Common::Helpers

module StackBuilder::Stack

    class NodeTask
        
        attr_reader :name

        attr_accessor :scale
        attr_accessor :prev_scale
        attr_accessor :sync

        attr_accessor :deleted
        
        attr_reader :counter
        attr_reader :parent_nodes
        attr_reader :child_nodes

        attr_reader :resource_sync
        attr_reader :manager

        SYNC_NONE  = 0  # All node instances processed asynchronously
        SYNC_FIRST = 1  # First node instance is processed synchronously and the rest asynchronously
        SYNC_ALL   = 2  # All node instances are processed synchronously
        
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

            case node_config['sync']
                when "first"
                    @sync = SYNC_FIRST
                when "all"
                    @sync = SYNC_ALL
                else
                    @sync = SYNC_NONE
            end

            if node_config.has_key?('targets')

                @logger.warn("Ignoring 'scale' attribute for '#{@name}' as that node has targets.") \
                    if node_config.has_key?("scale")

                @scale = 0
            else
                current_scale = manager.get_scale
                if current_scale==0
                    @scale = (node_config.has_key?("scale") ? node_config["scale"] : 1)
                else
                    @scale = current_scale
                end

                raise ArgumentError, "The scale for node \"#{@name}\" must be greater than 0." if @scale < 1
            end
            @prev_scale = @scale

            @targets = [ ]

            @node_mutex = Mutex.new
            @resource_sync = [ ]

            @deleted = false
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

                @resource_sync.size.step(current_scale - 1) do |i|
                    @resource_sync[i] ||= StackBuilder::Common::Semaphore.new
                    @resource_sync[i].signal
                end

                if current_scale>@scale

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

                if @scale>current_scale && !@deleted

                    @logger.debug("Scaling #{self} from #{current_scale} up to #{@scale}")

                    # Scale up

                    current_scale.step(@scale - 1) do |i|

                        sync = StackBuilder::Common::Semaphore.new
                        @resource_sync[i] = sync

                        threads << Thread.new {

                            begin
                                @logger.debug("Creating #{self} #{i}.")
                                $stdout.printf( "Creating node resource '%s[%d]'.\n",
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

            scale = (@deleted ? @manager.get_scale : @scale)
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
                    t.scale.times do |i|
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
            
            "(#{@name}, #{p}, #{c}, " +
                "Sync[#{@sync==SYNC_NONE ? "async" : @sync==SYNC_FIRST ? "first" : "alls"}], " +
                "Scale[#{manager.get_scale}])"
        end

        private

        def spawn_processing(i, events, threads, target = nil)

            if target.nil?
                target_manager = nil
                prev_scale = @prev_scale
            else
                target_manager = target.manager
                prev_scale = target.prev_scale
            end

            if target_manager.nil?
                $stdout.printf( "Processing node '%s[%d]'.\n", @name, i)
            else
                $stdout.printf( "Processing target node '%s[%d]' from %s.\n", target_manager.name, i, @name)
            end

            # If no scale up occurs then run only the given events.
            orchestrate_events = events.clone
            # If new VMs have been added to the cluster to scale up then add default events for the new VM.
            orchestrate_events = orchestrate_events.merge([ "create", "install", "configure" ]) if i >= prev_scale

            @logger.debug("Events for node '#{name}' instance #{i} build: " +
                "#{orchestrate_events.collect { |e| e } .join(", ")}") if @logger.debug?

            if @sync==SYNC_ALL || (i==0 && @sync==SYNC_FIRST)
                @manager.process(i, orchestrate_events, parse_attributes(@attributes, i), target_manager)
            else
                @resource_sync[i].wait if target.nil?
                threads << Thread.new {

                    begin
                        @manager.process(i, orchestrate_events, parse_attributes(@attributes, i), target_manager)

                    rescue Exception => msg

                        puts("Fatal Error: #{msg}")
                        @logger.debug(msg.backtrace.join("\n\t"))

                        raise StackBuilder::Common::StackOrchestrateError,
                            "Orchestrating node resource '#{name}[#{i}]' " +
                            "terminated with an error: #{msg}"
                    ensure
                        @resource_sync[i].signal if target.nil?
                    end
                }
            end
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

                elsif v =~ /^nodes\[.*\](.size)?$/

                    lookup_keys = v.split(/[\[\]]/).reject { |l| l == "nodes" || l.empty? }

                    l = lookup_keys.shift
                    node = @nodes[l]
                    unless node.nil?

                        node_attributes = node.manager.node_attributes
                        unless node_attributes.nil? || node_attributes.empty?

                            indexes = [ ]
                            values = [ ]

                            l = lookup_keys.shift
                            case l
                                when ".size"
                                    values << node.scale
                                when "*"
                                    indexes = (0..node.scale-1).to_a
                                when /\d+/
                                    indexes << l.to_i
                                else
                                    indexes << 0
                            end

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