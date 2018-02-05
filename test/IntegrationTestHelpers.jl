module IntegrationTestHelpers

using JuMP

using MIPVerify: find_adversarial_example
using MIPVerify: NeuralNetParameters
using MIPVerify: PerturbationParameters
using Base.Test

if Pkg.installed("Gurobi") == nothing
    using Cbc
    Solver = CbcSolver
else
    using Gurobi
    Solver = GurobiSolver
end

"""
Tests the `find_adversarial_example` function.
  - If `x0` is already classified in the target label, `expected_objective_value`
    should be 0.
  - If there is no adversarial example for the specified parameters, 
    `expected_objective_value` should be NaN.
  - If there is an adversarial example, checks that the objective value is as expected,
    and that the perturbed output for the target label exceeds the perturbed 
    output for all other labels by `tolerance`.
"""
function test_find_adversarial_example(
    nnparams::NeuralNetParameters, 
    x0::Array{T, N}, 
    target_selection::Union{Integer, Array{<:Integer, 1}}, 
    pp::PerturbationParameters, 
    norm_order::Real,
    tolerance::Real, 
    expected_objective_value::Real,
    solver_type::DataType,
    ) where {T<:Real, N} 
    d = find_adversarial_example(
        nnparams, x0, target_selection, solver_type, 
        pp = pp, norm_order = norm_order, tolerance = tolerance, rebuild=false)
    if d[:SolveStatus] == :Infeasible
        @test isnan(expected_objective_value)
    else
        if expected_objective_value == 0
            @test getobjectivevalue(d[:Model]) == 0
        else
            actual_objective_value = getobjectivevalue(d[:Model])
            # @test actual_objective_value≈expected_objective_value
            @test actual_objective_value/expected_objective_value≈1 atol=5e-5
            
            perturbed_output = getvalue(d[:PerturbedInput]) |> nnparams
            perturbed_target_output = maximum(perturbed_output[Bool[i∈d[:TargetIndexes] for i = 1:length(d[:Output])]])
            maximum_perturbed_other_output = maximum(perturbed_output[Bool[i∉d[:TargetIndexes] for i = 1:length(d[:Output])]])
            @test perturbed_target_output/(maximum_perturbed_other_output+tolerance)≈1 atol=5e-5
        end
    end
end

"""
Runs tests on the neural net described by `nnparams` for input `x0` and the objective values
indicated in `expected objective values`.

# Arguments
- `expected_objective_values::Dict`: 
   d[(target_selection, perturbation_parameter, norm_order, tolerance)] = expected_objective_value
   `expected_objective_value` is `NaN` if there is no perturbation that brings the image
   into the target category.
"""
function batch_test_adversarial_example(
    nnparams::NeuralNetParameters, 
    x0::Array{T, N},
    expected_objective_values::Dict
) where {T<:Real, N}
    for (test_params, expected_objective_value) in expected_objective_values
        (target_selection, pp, norm_order, tolerance) = test_params
        @testset "target label = $target_selection, $(string(pp)) perturbation, norm order = $norm_order, tolerance = $tolerance" begin
            test_find_adversarial_example(
                nnparams, x0, 
                target_selection, pp, norm_order, tolerance, expected_objective_value,
                Solver)
            end
        end
    end
end