module Evo

using ..Config
using ..Names
using ..Geo

using RecursiveArrayTools
using InformationMeasures
using SharedArrays
using Distributed
using Dates


export AbstractCreature, Evolution, step!, Tracer, step_for_duration!



abstract type AbstractCreature end


#==================== Example ==============================
#
Base.@kwdef mutable struct Creature <: AbstractCreature 
    chromosome::Vector{UInt32}
    phenotype::Union{Nothing, Hatchery.Profile}
    fitness::Vector{Float64}
    name::String
    generation::Int
    num_offspring::Int = 0
end
============================================================#

function validate_creature(C::DataType)
  @assert hasfield(C, :chromosome)
  @assert hasfield(C, :fitness)
  @assert hasfield(C, :name)
  @assert hasfield(C, :generation)
  @assert hasfield(C, :num_offspring)
end

Base.isequal(c1::C, c2::C) where C <: AbstractCreature = c1.name == c2.name
Base.isless(c1::C, c2::C) where C <: AbstractCreature = c1.fitness < c2.fitness


function crossover(parents::Tuple{AbstractCreature}...)
  @error "crossover needs to be implemented for the concrete creature type $(typeof(parents))"
end


function mutate!(parent::AbstractCreature; config=nothing)
  @error "mutate! needs to be implemented for the concrete creature type $(typeof(parent))"
end


function init_fitness(config::NamedTuple)
  Float64[-Inf for _ in 1:config.selection.d_fitness]
end


function init_fitness(template::Vector)
  Float64[-Inf for _ in template]
end


Base.@kwdef struct Tracer
    key::String
    callback::Function
    rate::Float64 = 1.0
end

function Tracer(tr::NamedTuple)
    Tracer(
        key=tr.key,
        callback=tr.callback,
        rate=:rate ∈ keys(tr) ? tr.rate : 1.0)
end


#=
mutable struct Trace
    d::Dict{String, SharedArray}
    tracers::Vector
end


function Trace(tracers, n_iterations, population_size)
    arr_size = (nprocs(), n_iterations, population_size...)
    d = [tr.key => SharedArray(fill(-Inf, arr_size...))
         for tr in tracers] |> Dict
    Trace(d, tracers)
end


function slice(trace::Trace; key, iteration)
    if
    trace.d[key][2:end, iteration, :, :]
end

#function slice(trace::Trace; key, ids, iteration)
#    trace.d[key][ids, iteration, :, :]
#end

function trace!(trace::Trace, evo)
    for tr in trace.tracers
        trace.d[tr.key][myid(), evo.iteration, :, :] = tr.callback.(evo.geo.deme)
    end
end

function trace!(evo)
    trace!(evo.trace2, evo)
end
=#

Base.@kwdef mutable struct Evolution
    config::NamedTuple
    logger
    geo::Geo.Geography
    fitness::Function
    iteration::Int = 0
    elites::Vector = []
    tracers::Vector = []
    trace::Dict = Dict()
    mutate::Function
    crossover::Function
end


function Evolution(config::NamedTuple;
                   creature_type::DataType,
                   fitness::Function,
                   tracers=[],
                   mutate::Function,
                   crossover::Function)
    logger = nothing # TODO
    geo = Geo.Geography(creature_type, config)
    Evolution(config=config,
              logger=logger,
              geo=geo,
              fitness=fitness,
              tracers=tracers,
              mutate=mutate,
              crossover=crossover)
end


function Evolution(config::String; kwargs...)
    cfg = Config.parse(config)
    Evolution(cfg; kwargs...)
end


function preserve_elites!(evo::Evolution)
  pop = sort(unique(g->g.name, [vec(evo.geo); evo.elites]), by=(x -> x.fitness))
  n_elites = evo.config.population.n_elites
  evo.elites = [deepcopy(pop[end-i]) for i in 0:(n_elites-1)]
end


function evaluate!(evo::Evolution, fitness::Function)
  Geo.evaluate!(evo.geo, fitness)
end


function trace!(evo::Evolution, callback::Function, key::String, sampling_rate::Float64=1.0)
    if !(key ∈ keys(evo.trace))
        evo.trace[key] = []
    end
    if rand() <= sampling_rate
        push!(evo.trace[key], callback.(evo.geo.deme))
    end
end


function trace!(evo::Evolution)
    for tr in evo.tracers
        trace!(evo, tr.callback, tr.key, tr.rate)
    end
end


function likeness(a, b)
    if a == b
        return 1.0
    end
    e = get_entropy(a)
    m = get_mutual_information(a, b)
    iszero(e) ? m : m / e
end


function step!(evo::Evolution; eval_children=true, measure_likeness=true, interaction_matrix=nothing)
    ranking = Geo.tournament(evo.geo, evo.fitness, interaction_matrix=interaction_matrix)
    parent_indices = ranking[end-1:end]
    parents = evo.geo[parent_indices]
    children = evo.crossover(parents..., config=evo.config)
    for child in children
        if rand() < evo.config.genotype.mutation_rate
            evo.mutate(child, config=evo.config)
        end
    end
    if eval_children
        for child in children
            evo.fitness(child, config=evo.config, interaction_matrix=interaction_matrix)
        end
    end
    graves = ranking[1:2]
    evo.geo[graves] = children
    preserve_elites!(evo)
    evo.iteration += 1
    trace!(evo)

    if measure_likeness
        parents = evo.geo[parent_indices]
        children = evo.geo[graves]
        # now, measure mutual information
        for child in children
            child.parents = [p.name for p in parents]
            child.likeness = [likeness(p.phenotype.results, child.phenotype.results) for p in parents]
        end
    end

    return (parents=parent_indices, children=graves)
end


function step_for_duration!(evo, duration; kwargs...)
    if !(:step ∈ keys(kwargs))
        step = step!
    else
        step = kwargs.data.step
    end
    start = now()
    start_iter = evo.iteration
    while now() - start < duration
        step(evo; kwargs...)
    end
    iters = evo.iteration - start_iter
    return iters
end




end # end module
