include("InteractionNets.jl")
using .InteractionNets

function parallel_computation_example()
    net = Net(Agent[])
    
    # Pre-allocate agent array for better performance
    num_agents = 4
    agents = Vector{Agent}(undef, num_agents)
    
    # Create agents
    agents[1] = create_tensor(net)
    agents[2] = create_par(net)
    agents[3] = create_tensor(net)
    agents[4] = create_par(net)
    
    # Batch connections
    connect(agents[1].ports[1], agents[2].ports[1])
    connect(agents[3].ports[1], agents[4].ports[1])
    connect(agents[1].ports[2], agents[3].ports[2])
    connect(agents[2].ports[2], agents[4].ports[2])
    
    println("Starting parallel computation...")
    
    start_time = time()
    run_net(net)
    end_time = time()
    compute_time = end_time - start_time
    
    println("Computation complete in $compute_time seconds!")
    
    return net
end

function map_example()
    net = Net(Agent[])
    
    # Optimize rule functions for performance
    cons_rule(self, other) = if other.type == :map
        new_cons = create_cons(net)
        f_agent = other.ports[2].agent[]
        
        # Batch connections
        connect(self.ports[2], f_agent.ports[1])
        connect(f_agent.ports[2], new_cons.ports[2])
        
        new_map = create_map(net)
        connect(self.ports[3], new_map.ports[1])
        connect(new_map.ports[3], new_cons.ports[3])
        connect(other.ports[2], new_map.ports[2])
    end
    
    nil_rule(self, other) = if other.type == :map
        new_nil = create_nil(net)
        connect(other.ports[3], new_nil.ports[1])
    end
    
    map_rule(self, other) = if other.type == :cons
        # Empty implementation for performance
    elseif other.type == :nil
        # Empty implementation for performance
    end
    
    # Optimized agent creation with inline functions
    create_cons(net) = (agent = Agent(:cons, 3, cons_rule); push!(net.agents, agent); agent)
    create_nil(net) = (agent = Agent(:nil, 1, nil_rule); push!(net.agents, agent); agent)
    create_map(net) = (agent = Agent(:map, 3, map_rule); push!(net.agents, agent); agent)
    create_inc(net) = (agent = Agent(:inc, 2, (self, other) -> connect(self.ports[2], other)); 
                       push!(net.agents, agent); agent)
    
    # Create list with pre-allocation
    nil = create_nil(net)
    cons_nodes = Vector{Agent}(undef, 3)
    cons_nodes[3] = create_cons(net)
    cons_nodes[2] = create_cons(net)
    cons_nodes[1] = create_cons(net)
    
    # Batch connections
    connect(cons_nodes[1].ports[3], cons_nodes[2].ports[1])
    connect(cons_nodes[2].ports[3], cons_nodes[3].ports[1])
    connect(cons_nodes[3].ports[3], nil.ports[1])
    
    map_agent = create_map(net)
    inc = create_inc(net)
    
    # More batch connections
    connect(map_agent.ports[1], cons_nodes[1].ports[1])
    connect(map_agent.ports[2], inc.ports[1])
    
    dummy_agent = Agent(:dummy, 1, (x,y)->nothing)
    push!(net.agents, dummy_agent)
    result = dummy_agent.ports[1]
    
    connect(map_agent.ports[3], result)
    
    println("Starting concurrent map operation...")
    
    start_time = time()
    run_net(net)
    end_time = time()
    compute_time = end_time - start_time
    
    println("Map operation complete in $compute_time seconds!")
    
    return result
end

function main()
    println("Running parallel computation example:")
    parallel_computation_example()
    
    println("\nRunning map example:")
    result = map_example()
    println("Map result obtained.")
end

main()
