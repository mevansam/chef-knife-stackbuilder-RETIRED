# Copyright (c) 2014 Mevan Samaratunga

require File.expand_path('../../../spec_helper', __FILE__)

include StackBuilder::Common::Helpers

class MockResource

    attr_accessor :name
    attr_accessor :processed_events

    attr_accessor :attributes

    def initialize(name)

        @name = name
        @processed_events = { }
        @attributes = { }

        @attributes['id'] = SecureRandom.uuid
    end

    def get_id
        @attributes['id']
    end

    def to_s

        e = @processed_events.each_pair.collect { |k,v| "#{k} => #{v}"}.join(', ')
        "(#{@name}: #{e})"
    end
end

class MockNodeProvider < StackBuilder::Stack::NodeProvider

    attr_reader :num_dynamic
    attr_reader :num_static

    attr_reader :resources

    def initialize

        @resources = { }

        @num_dynamic = 0
        @num_static = 0
    end

    def set_stack(stack, id)
        @id = id
    end

    def get_node_manager(node_config)

        case node_config['type']

            when 'dynamic'
                @num_dynamic += 1
                return MockDynamicNodeManager.new(@resources, node_config)
            when 'static'
                @num_static += 1
                return MockStaticNodeManager.new(@resources, node_config)
            else
                raise StackBuilder::Common::StackBuilderError,
                    'Invalid type: ' + node_config['type']
        end

    end
end

class MockDynamicNodeManager < StackBuilder::Stack::NodeManager

    attr_accessor :name

    def initialize(resources, node_config)

        @resources = resources
        @name = node_config['node']

        @events = [ ]
    end

    def get_name
        @name
    end

    def get_scale
        resource_nodes = @resources[@name]
        resource_nodes.nil? ? 0 : resource_nodes.size
    end

    def node_attributes
        attributes = [ ]
        @resources[@name].each { |resource_node| attributes << resource_node.attributes }

        attributes
    end

    def create(index)

        resource_nodes = @resources[@name]
        if resource_nodes.nil?
            resource_nodes = [ ]
            @resources[@name] = resource_nodes
        end

        resource_node = MockResource.new(name)
        resource_nodes[index] = resource_node

        # Add some sleep time
        sleep(1 + rand(2))

        puts "#{@name}[#{index}]: done creating resource instance ..."
    end

    def process(index, events, attributes, target = nil)

        resource_nodes = @resources[@name]
        raise StackBuilder::Common::StackBuilderError,
            "No resource nodes found for #{@name}." if resource_nodes.nil?

        resource_node = @resources[@name][index]
        raise StackBuilder::Common::StackBuilderError,
            "No resource node found at #{@name}[#{index}]." if resource_node.nil?

        resource_node.attributes.merge(attributes)
        events.each { |e| resource_node.processed_events[e] = Time.now.to_f }

        # Add some sleep time
        sleep(1 + rand(2))

        puts "#{@name}[#{index}]: done processing events '#{events.collect { |e| e }.join(", ")}'..."
    end

    def delete(index)

        resource_nodes = @resources[@name]

        # Delete last resource node
        resource_node = resource_nodes.delete_at(resource_nodes.size - 1)

        resource_nodes = @resources['DELETED']
        if resource_nodes.nil?
            resource_nodes = [ ]
            @resources['DELETED'] = resource_nodes
        end
        resource_nodes << resource_node

        puts "#{@name}[#{index}]: has been deleted"
    end
end

class MockStaticNodeManager < StackBuilder::Stack::NodeManager

    attr_accessor :name

    def initialize(resources, node_config)

        @resources = resources
        @name = node_config['node']
    end

    def get_name
        @name
    end

    def process(index, events, attributes, target = nil)

        resource_node = @resources[target.name][index]
        events.each { |e| resource_node.processed_events[@name + ':' + e] = Time.now.to_f }

        puts "#{target.name}[#{index}]: done processing events '#{events.collect { |e| e }.join(", ")}'..."
    end
end

describe StackBuilder::Stack do

    before(:all) do
        @logger = StackBuilder::Common::Config.logger
        @test_data_path = File.expand_path('../../../data', __FILE__)

        @provider = MockNodeProvider.new
        @stack = StackBuilder::Stack::Stack.new(@provider, @test_data_path + '/test_stack/stack_test.yml')
    end

    after(:all) do
    end

    it "should validate the initialized stack file" do

        nodes = @stack.nodes

        expect(nodes['A'].parent_nodes.empty?).to eq(true)

        expect(nodes['B'].parent_nodes).to \
            contain_exactly(nodes['A'])
        expect(nodes['C'].parent_nodes).to \
            contain_exactly(nodes['A'], nodes['D'])
        expect(nodes['D'].parent_nodes).to \
            contain_exactly(nodes['A'])
        expect(nodes['E'].parent_nodes).to \
            contain_exactly(nodes['A'], nodes['B'])
        expect(nodes['F'].parent_nodes).to \
            contain_exactly(nodes['A'], nodes['B'], nodes['C'])
        expect(nodes['G'].parent_nodes).to \
            contain_exactly(nodes['A'], nodes['C'])

        expect(nodes['A'].child_nodes).to \
            contain_exactly(nodes['B'], nodes['C'], nodes['D'], nodes['E'], nodes['F'], nodes['G'])
        expect(nodes['B'].child_nodes).to \
            contain_exactly(nodes['E'], nodes['F'])
        expect(nodes['C'].child_nodes).to \
            contain_exactly(nodes['F'], nodes['G'])
        expect(nodes['D'].child_nodes).to \
            contain_exactly(nodes['C'])

        expect(nodes['E'].child_nodes.empty?).to eq(true)
        expect(nodes['F'].child_nodes.empty?).to eq(true)
        expect(nodes['G'].child_nodes.empty?).to eq(true)
    end

    it "should orchestrate a stack file" do

        puts "\nBuilding the stack..."

        @stack.orchestrate
        resources = @provider.resources

        expect(resources.keys).to contain_exactly('B', 'C', 'D', 'E', 'F', 'G')
        expect(resources['B'].size).to eq(1)
        expect(resources['C'].size).to eq(1)
        expect(resources['D'].size).to eq(1)
        expect(resources['E'].size).to eq(1)
        expect(resources['F'].size).to eq(1)
        expect(resources['G'].size).to eq(1)

        expect( resources['E'][0].processed_events['create'] <
            resources['B'][0].processed_events['create'] ).to eq(true)
        expect( resources['E'][0].processed_events['create'] <
            resources['C'][0].processed_events['create'] ).to eq(true)
        expect( resources['F'][0].processed_events['create'] <
            resources['B'][0].processed_events['create'] ).to eq(true)
        expect( resources['F'][0].processed_events['create'] <
            resources['C'][0].processed_events['create'] ).to eq(true)
        expect( resources['G'][0].processed_events['create'] <
            resources['B'][0].processed_events['create'] ).to eq(true)
        expect( resources['G'][0].processed_events['create'] <
            resources['C'][0].processed_events['create'] ).to eq(true)

        expect( resources['B'][0].processed_events['create'] <
            resources['D'][0].processed_events['create'] ).to eq(true)
        expect( resources['C'][0].processed_events['create'] <
            resources['D'][0].processed_events['create'] ).to eq(true)

        expect( resources['D'][0].processed_events['create'] <
            resources['E'][0].processed_events['A:create'] ).to eq(true)
        expect( resources['D'][0].processed_events['create'] <
            resources['F'][0].processed_events['A:create'] ).to eq(true)
        expect( resources['D'][0].processed_events['create'] <
            resources['G'][0].processed_events['A:create'] ).to eq(true)
    end

    it "should scale up and down resources in the stack file" do

        resources = @provider.resources

        puts "\nScaling up node 'E' of the stack..."
        @stack.scale('E', 3)

        expect(resources.keys).to contain_exactly('B', 'C', 'D', 'E', 'F', 'G')
        expect(resources['B'].size).to eq(1)
        expect(resources['C'].size).to eq(1)
        expect(resources['D'].size).to eq(1)
        expect(resources['E'].size).to eq(3)
        expect(resources['F'].size).to eq(1)
        expect(resources['G'].size).to eq(1)

        ['B', 'E'].each do |name|

            resources[name].each do |resource_node|

                ['C', 'D', 'F', 'G'].each do |name|

                    expect( resource_node.processed_events['configure'] >
                        resources[name][0].processed_events['configure'] ).to eq(true)
                end
            end
        end

        puts "\nScaling up node 'F' of the stack..."
        @stack.scale('F', 2)

        expect(resources.keys).to contain_exactly('B', 'C', 'D', 'E', 'F', 'G')
        expect(resources['B'].size).to eq(1)
        expect(resources['C'].size).to eq(1)
        expect(resources['D'].size).to eq(1)
        expect(resources['E'].size).to eq(3)
        expect(resources['F'].size).to eq(2)
        expect(resources['G'].size).to eq(1)

        ['B', 'C', 'D', 'F'].each do |name|

            resources[name].each do |resource_node|

                ['E', 'G'].each do |name|

                    expect( resource_node.processed_events['configure'] >
                        resources[name][0].processed_events['configure'] ).to eq(true)
                end
            end
        end

        puts "\nScaling down node 'F' of the stack..."
        @stack.scale('F', 1)

        expect(resources.keys).to contain_exactly('B', 'C', 'D', 'E', 'F', 'G', 'DELETED')
        expect(resources['B'].size).to eq(1)
        expect(resources['C'].size).to eq(1)
        expect(resources['D'].size).to eq(1)
        expect(resources['E'].size).to eq(3)
        expect(resources['F'].size).to eq(1)
        expect(resources['G'].size).to eq(1)

        expect(resources['DELETED'].size).to eq(1)
        expect(resources['DELETED'][0].name).to eq('F')

        ['B', 'C', 'D', 'F'].each do |name|

            resources[name].each do |resource_node|

                ['E', 'G'].each do |name|

                    expect( resource_node.processed_events['configure'] >
                                    resources[name][0].processed_events['configure'] ).to eq(true)
                end
            end
        end

    end

    it "should destroy all resources created by a stack file" do

        resources = @provider.resources

        puts "\nDestroying the stack..."
        @stack.destroy

        expect(resources['DELETED'].size).to eq(9)
    end
end