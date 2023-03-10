#!/usr/bin/env julia

# Generates the verbose Julia job matrix YAML template. By generating the YAML we can more
# easily add additional Julia versions or OS's without risking introducing subtle mistakes
# when updatint the YAML by hand.
#
# Usage:
#
# julia gen/julia-template.jl > templates/julia.yml
#

# Julia versions available to run, not the versions enabled by default
const VERSIONS = ["1.6", "1.7", "1.8"]

# Julia versions available which can be enabled on nightly using `audit: "true"`. Useful for
# running new Julia versions before adding them to the list of default versions
const AUDIT_VERSIONS = []

# Julia version to use for the deprecation job(s). Ideally is the same version used as EIS.
const DEPRECATION_VERSION = "1.8"


# Indents each non-blank line by `n` spaces
indent(str, n) = replace(str, r"^(?=.*\S)"m => " " ^ n)

# The jobs used in the job matrix are controlled with GitLab CI rules which in pseudo-code
# would be written as `"1.0" ∈ julia`. In reality the `julia` list is actually a comma
# separated string (`julia = "1.0, 1.1, 1.2"`) which means our element-of check is a regular
# expression which determines if the element is included in the list.
function in_list(cond::AbstractString, haystack_name::AbstractString, needles::AbstractVector{<:AbstractString})
    "\$$(haystack_name) $cond /(^|[, ])$(join(map(needle -> "\\Q$needle\\E", needles), "|"))([, ]|\$)/"
end

function in_list(cond::AbstractString, haystack_name::AbstractString, needle::AbstractString)
    in_list(cond, haystack_name, [needle])
end

in_list(haystack_name::AbstractString, needle) = in_list("=~", haystack_name, needle)
not_in_list(haystack_name::AbstractString, needle) = in_list("!~", haystack_name, needle)

abstract type Job end

struct MatrixJob <: Job
    version::String
    os::String
    platform::Union{String,Nothing}
    executor::String
    high_memory::Union{Bool,Nothing}
end

function MatrixJob(version, os; platform=nothing, executor="shell", high_memory=nothing)
    MatrixJob(version, os, platform, executor, high_memory)
end

# Runner tags which are associated with a job
function tags(job::Job)
    os_tag = job.os == "mac" ? "macos" : job.os
    executor_tag = job.executor !== nothing ? "$(job.executor)-ci" : nothing
    high_memory_tag = job.high_memory == true ? "high-memory" : nothing

    tags = [os_tag, job.platform, executor_tag, high_memory_tag]
    filter!(!isnothing, tags)

    return tags
end

# Lists all variations of a platform name. Used mainly to control if a job should be run
# based upon what is specified in the YAML job matrix `platform` variable.
function platforms(job::Job)
    if job.platform == "x86_64" || job.platform === nothing
        ["x86_64", "x86"]
    else
        [job.platform]
    end
end

# The templates used in `extends`
function extensions(job::Job)
    [
        ".test_$(job.executor)",
        ".test_$(replace(job.version, '.' => '_'))",
    ]
end

# Job name typically of the form: `$julia_version ($os, $platform, $high_memory)`. Note some
# elements are left out when it is unambiguous to make the name shorter.
function name(job::Job)
    job_name = titlecase(job.version)

    details = String[titlecase(job.os)]
    job.os == "linux" && push!(details, first(platforms(job)))
    job.high_memory == true && push!(details, titlecase("high-memory"))
    !isempty(details) && (job_name *= " ($(join(details, ", ")))")

    return job_name
end

# Any global variables that should be associated with the job
function variables(job::Job)
    vars = Dict{String,String}()

    # Use CLI git as opposed to libgit2 to hopefully avoid potential network issues on Mac
    # https://gitlab.invenia.ca/invenia/gitlab-ci-helper/-/issues/31
    # This option was added in 1.7 and backported to 1.6.6
    if job.os == "mac"
        vars["JULIA_PKG_USE_CLI_GIT"] = "true"
    end

    return vars
end

function rules(job::Job)::Vector{Dict{String,Any}}
    job_name_quoted = "\"$(name(job))\""

    # Determines if a job should run based upon what is specified in the job matrix
    # variables: `julia`, `os`, and `platform`. As job should not be run if it is
    # specifically listed as part of `exclude`.
    job_matrix_conditions = [
        in_list("julia", job.version),
        in_list("os", job.os),
        in_list("platform", platforms(job)),
        not_in_list("exclude", job_name_quoted)
    ]

    if job.high_memory !== nothing
        pushfirst!(job_matrix_conditions, "\$high_memory == \"$(job.high_memory)\"")
    end

    conditions = if job.version == "nightly"
        cond = join(job_matrix_conditions, " && ")
        # run optionally except on pipelines
        [
            # Job name syntax needs to go first to override optional jobs
            Dict("if" => in_list("include", job_name_quoted)),
            Dict(
                "if" => "\$CI_PIPELINE_SOURCE != \"schedule\" && $cond",
                "when" => "manual",
            ),
            Dict("if" => "\$CI_PIPELINE_SOURCE == \"schedule\" && $cond"),
        ]
    else
        map([
            join(job_matrix_conditions, " && "),

            # Alternatively, run the job if it is specifically listed as part of `include`.
            in_list("include", job_name_quoted),
        ]) do c
            Dict("if" => c)
        end
    end

    return conditions
end

function priority_rules(job::Job)::Vector{Dict{String,Any}}
    return if job.os == "mac"
        [
            Dict(
                "#" => """
                    # Currently we have too many jobs for the mac runner(s) in place,
                    # so not running for research repos, and not running on nightly
                    # https://gitlab.invenia.ca/invenia/gitlab-ci-helper/-/issues/92
                    # https://gitlab.invenia.ca/invenia/gitlab-ci-helper/-/issues/107
                    """,
                "if" => "\$CI_PROJECT_NAMESPACE == \"invenia/research\" || \$GITLAB_USER_LOGIN =~ /^nightly/",
                "when" => "never",
            )
        ]
    else
        []
    end
end


function retries(job::Job)
    # `when` should be update to return of list of conditions
    return job.os != "mac" ? Dict{String, String}() : Dict(
            "max" => "2",
            "when" => "runner_system_failure"
        )
end

# Write out YAML based upon the dictionary created from `rules(::Job)`
function render_rule(io::IO, rule)
    if "#" in keys(rule)
        print(io, rule["#"])
        endswith(rule["#"], '\n') || println(io)
    end

    print(io, "- if: $(rule["if"])")

    if "allow_failure" in keys(rule)
        print(io, "\n  allow_failure: $(rule["allow_failure"])")
    end

    if "when" in keys(rule)
        print(io, "\n  when: $(rule["when"])")
    end

    if "blank-line" in keys(rule)
        println(io)
    end
end

# Write out YAML based upon an Job instant
function render(io::IO, job::Job)
    job_name_quoted = "\"$(name(job))\""
    println(io, "$job_name_quoted:")

    _tags = tags(job)
    if !isempty(_tags)
        println(io, indent("tags:", 2))
        println(io, indent(join(["- $tag" for tag in _tags], '\n'), 4))
    end

    _variables = variables(job)
    if !isempty(_variables)
        println(io, indent("variables:", 2))
        println(io, indent(join(["$k: \"$v\"" for (k, v) in _variables], '\n'), 4))
    end

    _rules = vcat(priority_rules(job), rules(job))
    if !isempty(_rules)
        println(io, indent("rules:", 2))
        println(io, indent(join([sprint(render_rule, rule) for rule in _rules], '\n'), 4))
    end

    _retries = retries(job)
    if !isempty(_retries)
        println(io, indent("retry:", 2))
        println(io, indent(join(["$k: $v" for (k, v) in _retries], '\n'), 4))
    end

    _extensions = extensions(job)
    if !isempty(_extensions)
        println(io, indent("extends:", 2))
        println(io, indent(join(["- $ext" for ext in _extensions], '\n'), 4))
    end
end


struct DeprecationJob{J <: Job} <: Job
    job::J
end

DeprecationJob(args...; kwargs...) = DeprecationJob(MatrixJob(args...; kwargs...))

function Base.getproperty(job::DeprecationJob, field::Symbol)
    if field === :job
        getfield(job, :job)
    else
        getfield(getfield(job, :job), field)
    end
end

function name(job::DeprecationJob)
    job_name = "Deprecations"

    parts = String[]
    job.high_memory == true && push!(parts, titlecase("high-memory"))
    !isempty(parts) && (job_name *= " ($(join(parts, ", ")))")

    return job_name
end

function variables(job::DeprecationJob)
    Dict("JULIA_DEPWARN" => "error")
end

function rules(job::DeprecationJob)::Vector{Dict{String,Any}}
    _rules = invoke(rules, Tuple{Job}, job)

    # When deprecations are explicitly not allowed we'll disallow the job to fail. Note we
    # are also respecting the version/os/platform rules.
    allow_deprecations_cond = "\$allow_deprecations == \"false\""
    no_deprecation_rules = [
        Dict(
            "if" => join([allow_deprecations_cond, r["if"]], " && "),
            "allow_failure" => false,
        )
        for r in _rules
    ]

    no_deprecation_rules[1]["#"] = "# Allows packages to state that all deprecations have been addressed and new ones should cause failures"
    no_deprecation_rules[end]["blank-line"] = true

    # Alternative rule to check when `no_deprecation_rules` fails. Runs deprecation job but
    # allows failures.
    allow_deprecation_rules = [
        Dict(
            "if" => r["if"],
            "allow_failure" => true,
        )
        for r in _rules
    ]

    return [no_deprecation_rules; allow_deprecation_rules]
end

struct AuditJob{J <: Job} <: Job
    job::J
end

AuditJob(args...; kwargs...) = AuditJob(MatrixJob(args...; kwargs...))

function Base.getproperty(job::AuditJob, field::Symbol)
    if field === :job
        getfield(job, :job)
    else
        getfield(getfield(job, :job), field)
    end
end

function rules(job::AuditJob)::Vector{Dict{String,Any}}
    _rules = invoke(rules, Tuple{Job}, job)

    # When `audit: "true"` is specified we'll run this job when run as a nightly user even
    # when the version of this job is not included in the job matrix `version` variable.
    audit_conditions = [
        "\$GITLAB_USER_LOGIN =~ /^nightly/",
        "\$audit == \"true\"",
        "\$CI_PROJECT_NAME != \"TestJuliaTemplate.jl\"",
        in_list("os", job.os),
    ]

    job.version ∉ AUDIT_VERSIONS  && push!(audit_conditions, in_list("julia", job.version))

    if job.high_memory !== nothing
        pushfirst!(audit_conditions, "\$high_memory == \"$(job.high_memory)\"")
    end

    audit_rule = Dict(
        "if" => join(audit_conditions, " && "),
        "allow_failure" => true,
        "#" => """
            # Check the nightly dashboard for audit job warnings
            # Note: Skip auditing in the TestJuliaTemplate.jl as the tests there are sensitive to `allow_failure` changes
            """,
        "blank-line" => true,
    )

    return [audit_rule; _rules]
end

function jobs()
    jobs = Job[
        DeprecationJob(DEPRECATION_VERSION, "linux", platform="x86_64", executor="docker", high_memory=false),
        DeprecationJob(DEPRECATION_VERSION, "linux", platform="x86_64", executor="docker", high_memory=true),
        Iterators.flatten([
            MatrixJob(version, "mac", executor="shell"),
            MatrixJob(version, "linux", platform="x86_64", executor="docker", high_memory=false),
            MatrixJob(version, "linux", platform="x86_64", executor="docker", high_memory=true),
            # MatrixJob(version, "linux", platform="aarch64", executor="docker", high_memory=false),
            # MatrixJob(version, "linux", platform="aarch64", executor="docker", high_memory=true),
        ] for version in VERSIONS)...
    ]

    map(jobs) do job
        if job isa MatrixJob && (job.version in AUDIT_VERSIONS)
            AuditJob(job)
        else
            job
        end
    end
end

function render(io::IO, jobs::Vector{<:Job})
    first_job = true
    first_deprecation_job = true
    prev_version = nothing

    for job in jobs
        if first_job
            first_job = false
        else
            # Blank line between jobs
            println(io)

            # Add extra space between Julia version changes
            job.version != prev_version && println(io)
        end

        if job isa DeprecationJob && first_deprecation_job
            println(io, "# Test for deprecations using Linux x86_64 and the same Julia version used by EIS")
            first_deprecation_job = false
        end

        render(io, job)

        prev_version = job.version
    end
end


if @__FILE__() == abspath(PROGRAM_FILE)
    julia_prefix_path = joinpath(@__DIR__, "julia-prefix.yml")
    write(stdout, read(julia_prefix_path, String))
    render(stdout, jobs())
end
