GitLab CI for Julia Packages
============================

Building a Julia package on GitLab CI is very similar to [how it is done using Travis CI](https://docs.travis-ci.com/user/languages/julia).
The following documentation is meant for those interested in customizing their
*.gitlab-ci.yml* files. If you are just getting started you can use the
[example *.gitlab-ci.yml*](https://gitlab.invenia.ca/invenia/gitlab-ci-helper/raw/master/examples/gitlab-ci.yml)

The GitLab CI configuration file is laid out in multiple jobs that look like:

```yaml
"1.6 (Linux, x86_64)":  # Job title
  tags:
    - linux   # GitLab CI runner tags which specify which runner can run this
    - x86_64  # All of the tags must be associated with a single runner
  variables:
    JULIA_VERSION: "1.6"  # Specifies the version of Julia to run on
  <<: *test_shell         # YAML anchor used to avoid duplicating script information
```

Each of these jobs can be modified to test your package against different versions of Julia
and operating systems. When modifying the job you only need to change the values as
indicated by: `$VERSION`, `$OS_DESCRIPTION`, and `$TAGS`. Note typically the language
prefix "Julia" is left out.

```yaml
"$VERSION ($FORMAL_TAGS)":
  tags:
    - $TAGS
    - ...
  variables:
    JULIA_VERSION: "$VERSION"
  <<: *test_shell
```

- `$VERSION`: Can be any Julia version (similar to Travis CI) using the following formats:
    - `<major>.<minor>` = "0.4", latest version of Julia 0.4
    - `<major>.<minor>.<patch>` = "0.4.7", specifically Julia 0.4.7
    - `<major>.<minor>-` = "0.7-", latest pre-release version of Julia 0.7

- `$TAGS`: Specifies the runner to use to run the job. Used to specify what OS to run on:
    - *macos* = Run on any version of macOS (Sierra onwards)
    - *linux* = Run on any flavor of Linux
    - *debian* = Run on any version of Debian
    - *shell-ci* = Run on a GitLab CI shell runner
    - *docker-ci* = Run on a GitLab CI Docker runner
    - *high-memory* = Run on a Linux Docker runner with a higher memory limit (currently 16GB)
    - *low-memory* = Run on a Linux Docker runner with any memory limit (most runners have 8GB)
    - *x86_64* = Run on an AMD/Intel 64 bit instance
    - *aarch64* = Run on an ARM instance
    - *docker-build* = Run on a shell runner capable of building docker images
    - *account-id-#* = Run on an instance launched from `#` where `#` is an AWS account number (used for testing experimental changes)

    Tags can be combined which means that a runner needs to have all of the specified tags
    in order for the job to be run on that runner. For example to run on Linux without docker you
    can use the tags: *linux*, *shell-ci*

    To see what runners exist and what tags are specified with those runners see the [GitLab
    administration section](https://gitlab.invenia.ca/admin/runners)

- `$FORMAL_TAGS`: Human readable combination of tags used. Examples include:
    - *macos* = "Mac"
    - *linux, x86_64* = "Linux, x86_64"

Since the majority of the job work is the same and only differs in environments we make use
of YAML anchors in order to replicate duplicate content:

```yaml
.test_shell: &test_shell
  artifacts:
    name: "$CI_JOB_NAME coverage"
    expire_in: 1 week
    paths:
      - "$CI_JOB_NAME coverage/"
  before_script:
    - curl -sSL -o julia-ci https://gitlab-ci-token:${CI_JOB_TOKEN}@gitlab.invenia.ca/invenia/gitlab-ci-helper/raw/master/julia-ci
    - chmod +x julia-ci
    - ./julia-ci install $JULIA_VERSION
  script:
    - source julia-ci export
    - julia -e "Pkg.clone(pwd()); Pkg.build(\"$PKG_NAME\"); Pkg.test(\"$PKG_NAME\"; coverage=true)"
    - ./julia-ci coverage
  after_script:
    - ./julia-ci clean
```

We break up the script into `before_script`, `script`, and `after_script` to help denote
failures in the code we are testing and the setup/teardown process. For example a failure
in `Pkg.test` will still allow the cleanup step to run.

## Coverage Parsing

Currently GitLab only supports an overall coverage percentage which is available as a
[badge](https://docs.gitlab.com/ce/user/project/pipelines/settings.html#test-coverage-report-badge).
However, you can download the coverage files and report as artifacts from your repo's Pipelines page.

## References

- [GitLabHQ julia .gitlab-ci.yml example](https://github.com/gitlabhq/gitlabhq/blob/master/vendor/gitlab-ci-yml/Julia.gitlab-ci.yml)
