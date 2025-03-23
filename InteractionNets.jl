module InteractionNets

export Agent, Port, Net, connect, interact, run_net
export create_tensor, create_par

mutable struct Port
    agent::Ref{Any}
    slot::Int
end

mutable struct Agent
    type::Symbol
    ports::Vector{Port}
    rule::Function
    active::Bool  # Track if agent is active
end

struct Net
    agents::Vector{Agent}
    active_pairs::Channel{Tuple{Int,Int}}  
    processed::Set{Tuple{Int,Int}}  # Track processed pairs
end

function Agent(type::Symbol, arity::Int, rule::Function)
    ports = [Port(Ref(nothing), 0) for _ in 1:arity]
    agent = Agent(type, ports, rule, true)
    for (i, port) in enumerate(ports)
        port.agent[] = agent
        port.slot = i
    end
    return agent
end

function Net(agents::Vector{Agent})
    # Use threads count for channel sizing
    channel_size = max(length(agents) * 2, Threads.nthreads() * 4)
    active_pairs = Channel{Tuple{Int,Int}}(channel_size)
    processed = Set{Tuple{Int,Int}}()
    return Net(agents, active_pairs, processed)
end

function connect(p1::Port, p2::Port)
    if p1.agent[] === nothing || p2.agent[] === nothing
        error("Cannot connect to a null port")
    end
    
    p1.agent[].ports[p1.slot] = p2
    p2.agent[].ports[p2.slot] = p1
    
    # Mark both agents as active when connected
    p1.agent[].active = true
    p2.agent[].active = true
    
    return nothing
end

function find_active_pairs!(net::Net)
    active_count = 0
    
    # Pre-allocate for lookup optimizations
    n = length(net.agents)
    
    # Scan for potential active pairs
    for i in 1:n
        agent1 = net.agents[i]
        if !agent1.active || length(agent1.ports) == 0
            continue
        end
        
        p1 = agent1.ports[1]
        if p1.agent[] === nothing || p1.agent[] === agent1
            continue
        end
        
        agent2 = p1.agent[]
        j = findfirst(a -> a === agent2, net.agents)
        if j === nothing || j ≤ i  # Only process each pair once
            continue
        end
        
        # Check if this is an active pair
        if p1.slot == 1 && agent2.active
            # Create a unique identifier for this pair
            pair_id = (i, j)
            pair_id_rev = (j, i)
            
            # Skip if already processed
            if pair_id ∈ net.processed || pair_id_rev ∈ net.processed
                continue
            end
            
            # Add to the set of active pairs
            push!(net.processed, pair_id)
            
            # Add to channel
            put!(net.active_pairs, pair_id)
            active_count += 1
        end
    end
    
    return active_count
end

function interact!(net::Net, i::Int, j::Int)
    agent1 = net.agents[i]
    agent2 = net.agents[j]
    
    # Apply the interaction rule
    agent1.rule(agent1, agent2)
    
    # Look for new active pairs
    find_active_pairs!(net)
end

function run_net(net::Net; timeout=5.0, max_steps=1000)
    println("Looking for active pairs...")
    # Initial active pairs search
    find_active_pairs!(net)
    
    println("Active pairs found: $(isready(net.active_pairs) ? "yes" : "no")")
    
    # Prepare worker tasks
    num_workers = Threads.nthreads()
    println("Starting $num_workers worker tasks")
    
    # Create a task pool
    tasks = Vector{Task}(undef, num_workers)
    
    # Start time for timeout tracking
    t_start = time()
    step_count = 0
    
    # Shared atomic variables for coordination
    done = Threads.Atomic{Bool}(false)
    
    # Launch worker tasks
    for id in 1:num_workers
        tasks[id] = Threads.@spawn begin
            while !done[]
                try
                    if isready(net.active_pairs)
                        # Get next pair to process
                        i, j = take!(net.active_pairs)
                        
                        println("Worker $id processing interaction between agents $i and $j")
                        
                        # Process the interaction
                        interact!(net, i, j)
                        
                        # Update step counter
                        step_count += 1
                        
                        # Check termination conditions
                        if step_count >= max_steps || time() - t_start > timeout
                            Threads.atomic_xchg!(done, true)
                        end
                    else
                        # No more pairs to process
                        if !isready(net.active_pairs)
                            Threads.atomic_xchg!(done, true)
                        end
                        
                        # Small sleep to avoid busy-waiting
                        sleep(0.001)
                    end
                catch e
                    if isa(e, InvalidStateException) && e.state == :closed
                        println("Worker $id exiting (channel closed)")
                        break
                    else
                        println("Worker $id encountered error: $e")
                        rethrow()
                    end
                end
            end
        end
    end
    
    # Wait until done or timeout
    while !done[] && time() - t_start < timeout
        if isready(net.active_pairs)
            sleep(0.1)
        else
            # If channel is empty and no active pairs are being processed, we're done
            if !isready(net.active_pairs)
                Threads.atomic_xchg!(done, true)
            end
            sleep(0.1)
        end
    end
    
    # Signal all workers to stop
    Threads.atomic_xchg!(done, true)
    
    println("Closing channel and cleaning up")
    # Close the channel
    close(net.active_pairs)
    
    # Wait for all tasks to complete
    for task in tasks
        wait(task)
    end
    
    println("Run complete")
    return net
end

function tensor_rule(self, other)
    if other.type == :par
        println("Executing tensor * par interaction rule")
        # More efficient connection
        aux1_self, aux2_self = self.ports[2], self.ports[3]
        aux1_other, aux2_other = other.ports[2], other.ports[3]
        
        # Batch connections for better cache locality
        connect(aux1_self, aux1_other)
        connect(aux2_self, aux2_other)
    else
        println("No interaction rule for tensor * $(other.type)")
    end
end

function par_rule(self, other)
    if other.type == :tensor
        println("Executing par * tensor interaction rule")
        # Delegate to tensor_rule for consistency
        tensor_rule(other, self)
    else
        println("No interaction rule for par * $(other.type)")
    end
end

function create_tensor(net::Net)
    println("Creating tensor agent")
    agent = Agent(:tensor, 3, tensor_rule)
    push!(net.agents, agent)
    return agent
end

function create_par(net::Net)
    println("Creating par agent")
    agent = Agent(:par, 3, par_rule)
    push!(net.agents, agent)
    return agent
end

end
