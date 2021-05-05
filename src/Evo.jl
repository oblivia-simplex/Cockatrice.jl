module Evo

import YAML

using ..Config
using ..Names
using ..Geo

#Tracer = Geo.Tracer

using RecursiveArrayTools
using Distributed


export AbstractCreature, Evolution, step!



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

function step!(evo::Evolution; eval_children=false)
    ranking = Geo.tournament(evo.geo, evo.fitness)
    parents = evo.geo[ranking[end-1:end]]
    children = evo.crossover(parents...)
    if eval_children
        evo.fitness.(children)
    end
    for child in children
        if rand() < evo.config.genotype.mutation_rate
            evo.mutate(child, config=evo.config)
        end
    end
    graves = ranking[1:2]
    evo.geo[graves] = children
    preserve_elites!(evo)
    evo.iteration += 1
    trace!(evo)
    return
end


function step_for_duration!(evo, duration; kwargs...)
    start = now()
    while now() - start < duration
        Evo.step!(evo; kwargs...)
    end
    return
end




end # end module
