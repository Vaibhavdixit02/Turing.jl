
doc"""
    IS(n_particles::Int)

Importance sampler.

Usage:

```julia
IS(1000)
```

Example:

```julia
@model example begin
  ...
end

sample(example, IS(1000))
```
"""
immutable IS <: InferenceAlgorithm
  n_samples   ::  Int
  IS(n) = new(n)
end

type ImportanceSampler{IS} <: Sampler{IS}
  alg         ::  IS
  samples     ::  Vector{Sample}
  logweights  ::  Array{Float64}
  logevidence ::  Float64
  predicts    ::  Dict{Symbol,Any}
  function ImportanceSampler(alg::IS)
    samples = Array{Sample}(alg.n_samples)
    logweights = zeros(Float64, alg.n_samples)
    logevidence = 0
    predicts = Dict{Symbol,Any}()
    new(alg, samples, logweights, logevidence, predicts)
  end
end

function sample(model::Function, alg::IS)
  global sampler = ImportanceSampler{IS}(alg);
  spl = sampler

  n = spl.alg.n_samples
  for i = 1:n
    consume(Task(()->model(vi = VarInfo(), sampler = spl)))
    spl.samples[i] = Sample(spl.logevidence, spl.predicts)
    spl.logweights[i] = spl.logevidence
    spl.logevidence = 0
    spl.predicts = Dict{Symbol,Any}()
  end
  spl.logevidence = logsum(spl.logweights) - log(n)
  chn = Chain(exp(spl.logevidence), spl.samples)
  return chn
end

assume(spl::ImportanceSampler{IS}, d::Distribution, vn::VarName, varInfo::VarInfo) = rand(d)

function observe(spl::ImportanceSampler{IS}, d::Distribution, value, varInfo::VarInfo)
  spl.logevidence += logpdf(d, value)
end

function predict(spl::ImportanceSampler{IS}, name::Symbol, value) spl.predicts[name] = value
end
