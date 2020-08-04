struct Context{T, M}
    model::M
    var_id_to_moi_indices::OrderedDict{UInt64,Vector{MOI.VariableIndex}}
    id_to_variables::OrderedDict{UInt64,Any}
end

function Context{T}(optimizer) where {T}
    model = MOIB.full_bridge_optimizer(MOIU.CachingOptimizer(MOIU.UniversalFallback(MOIU.Model{T}()),
    optimizer), T)
    Context{T, typeof(model)}(model, OrderedDict{UInt64,Vector{MOI.VariableIndex}}(), OrderedDict{UInt64,Any}())
end