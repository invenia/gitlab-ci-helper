Supporting a New Julia Release
==============================

New versions of Julia are released semi-annually and we strive to have our packages support the latest release.
This document serves as a guide to updating the `gitlab-ci-helper` repository to enable support for a new Julia release.

Whenever the first release candidate for a new Julia version is available (we'll call this version X.Y), the following phases should occur:

1. [Add Dockerfiles support for Julia version X.Y](#add-ci-support)
2. [Add CI support for Julia version X.Y](#add-ci-support)
3. [Audit package compatibility with Julia X.Y](#audit-package-compatibility)
4. [Update package compatibility with Julia X.Y](#update-package-compatibility)
5. [Update EIS to use Julia X.Y](#update-eis)

A question you may be asking yourself is: why do we care if our packages support the latest Julia release?
There are a few reasons why we strive to support the latest version of Julia:

- Our test suite is fairly exhaustive and has proven to be useful in catching bugs in package dependencies and Julia itself, so having our packages run on the latest Julia version helps keep the language and ecosystem strong and suitable for our needs.
- We will want to switch EIS to use a newer version of Julia at some point, so as to benefit from improvements made to the language, and we want to keep that switch easy.
- Writing code that supports the latest version is much faster than updating code to support that version afterwards, so supporting each new version as soon as possible makes updating to future versions easier.
- Keeping our packages up-to-date with changes in the language encourages our team members to keep up-to-date which is good for their professional development and in turn promotes open-source contributions which we believe benefits Invenia in the long-term.
- Filing issues against open-source packages shows that Invenia is active member of the Julia community which can help us to recruit talent

## Add Dockerfiles support

In order to execute jobs that use the Docker runners we need to update Dockerfiles to build the appropriate Docker images for Julia version X.Y.
Note the Dockerfiles support update can be done safely at any time after a X.Y pre-release tag has been create and Julia binary is available.
The following assumes that ARM runners are available. The `aarch64` jobs should be ignored if no ARM linux runners are up.

To update Dockerfiles you need to add in jobs in the [`.gitlab-ci.yml`](https://gitlab.invenia.ca/invenia/Dockerfiles/-/blob/master/.gitlab-ci.yml) to build the Docker images for the version in question.
Specifically new entries as shown in the template below need to be added in the appropriate sections of the CI configuration:

```yaml
.X_Y:
  variables:
    VERSION: "X.Y"
  extends: .restricted  # `.restricted` avoids running these jobs as part of a PR


### julia-bin (build) ###

"julia-bin (X.Y, x86_64)":
  extends: [.julia-bin, .X_Y, .x86_64]

"julia-bin (X.Y, aarch64)":
  extends: [.julia-bin, .X_Y, .aarch64]


### julia-bin (manifest) ###

"julia-bin (X.Y)":
  needs: ["julia-bin (X.Y, x86_64)", "julia-bin (X.Y, aarch64)"]
  extends: [.julia-bin-manifest, .X_Y]


### julia-baked (build) ###

"julia-baked (X.Y, x86_64)":
  needs: ["julia-bin (X.Y, x86_64)"]
  extends: [.julia-baked, .X_Y, .x86_64]

"julia-baked (X.Y, aarch64)":
  needs: ["julia-bin (X.Y, aarch64)"]
  extends: [.julia-baked, .X_Y, .aarch64]


### julia-baked (manifest) ###

"julia-baked (X.Y)":
  needs: ["julia-baked (X.Y, x86_64)", "julia-baked (X.Y, aarch64)"]
  extends: [.julia-baked-manifest, .X_Y]


### julia-gitlab-ci (build) ###

"julia-gitlab-ci (X.Y, x86_64)":
  needs: ["julia-baked (X.Y, x86_64)"]
  extends: [.julia-gitlab-ci, .X_Y, .x86_64]

"julia-gitlab-ci (X.Y, aarch64)":
  needs: ["julia-baked (X.Y, aarch64)"]
  extends: [.julia-gitlab-ci, .X_Y, .aarch64]


### julia-gitlab-ci (manifest) ###

"julia-gitlab-ci (X.Y)":
  needs: ["julia-gitlab-ci (X.Y, x86_64)", "julia-gitlab-ci (X.Y, aarch64)"]
  extends: [.julia-gitlab-ci-manifest, .X_Y]
```

## Add Registry support

Go to the [Invenia Package Registry](https://gitlab.invenia.ca/invenia/PackageRegistry) and add the following to the CI configuration:
```yaml
"X.Y Registry Tests":
  variables:
    JULIA_VERSION: "X.Y"
  extends: .registry_tests
```

The entry for the current version should remain in use but any older versions should be removed.

## Add CI support

In order to have the GitLab CI support Julia version X.Y you'll need to perform the following steps:

1. Edit [/templates/hidden-jobs.yml] and add the following entry just prior to `.test_nightly` making sure to update `X_Y` and `X.Y` appropriately:

    ```yaml
    .test_X_Y:
      variables:
        JULIA_VERSION: "X.Y"
        audit: "true"
      allow_failure: true
    ```

2. Edit "gen/julia-template.jl" and add version X.Y to list of `VERSIONS` and `AUDIT_VERSIONS`

3. Re-generate "templates/julia.yml" by running `julia gen/julia-template.jl > templates/julia.yml`

4. Create, and merge, a merge request with these changes with the title "Support Julia X.Y"

At this point the CI is capable of running Julia tests on version X.Y but is not yet part of the default job matrix.

Take note that using the `audit: "true"` will run Julia X.Y jobs during the [nightly CI runs] without allowing failures.
Doing this allows us to discover which of our packages is incompatible with the new version of Julia.
Additional details can be found in the following [section](#audit-package-compatibility).


## Audit package compatibility

To verify which packages are incompatible with this revision, we'll use our [nightly CI runs] to alert us of packages that fail tests when using Julia version X.Y.
We also want to avoid having the nightly CI fail continuously night-after-night, so we should only proceed with this step once we have some time (about a day) to catalog and mitigate the failures.
Ideally the verification would take place shortly after [adding CI support](#add-ci-support) as the earlier we file issues the more likely they are to be addressed.

1. Create a [group milestone](https://gitlab.invenia.ca/groups/invenia/-/milestones) named "Julia X.Y"
2. Add version X.Y into the default job matrix.
   Create a merge request by editing [/templates/julia.yml] and update the global `julia` variable at the top of the file to include version X.Y.
3. Communicate with those performing [nightly](https://gitlab.invenia.ca/invenia/wiki/-/blob/master/dev/nightly.md) duties about the audit and to expect failures relating to Julia X.Y.
   Be sure to mention the MR you just created.
4. Once the merge request has been merged the next scheduled nightly jobs to run will include version incompatibility failures.
   Typically this means waiting until the next day.
5. Create issues on each failed package attaching the milestone "Julia X.Y" and making sure to reference the failed pipeline.
6. Make MRs, and merge, for each failed package by changing their `.gitlab-ci.yml` with:

    ```yaml
    # Remove when the package becomes compatible with this version of Julia:
    # LINK-TO-ISSUE
    .test_X_Y:
      allow_failure: true
    ```

7. Require, by default, that all CI test pass on Julia X.Y.
   This will ensure that all packages currently compatible with Julia X.Y retain compatibility from now on. Make, and merge, a MR in `gitlab-ci-helper` by updating `.test_X_Y` in [/templates/hidden-jobs.yml] with the removal of `allow_failure` and `audit = "true"`:

    ```yaml
    .test_X_Y:
      variables:
        JULIA_VERSION: "X.Y"
    ```

   Additionally, update the "Julia Template Test" CI job in [.gitlab-ci.yml] to require Julia X.Y to no longer allow failures.
   To do this just by adding the following at the end of the `GITLAB_CI_CONFIG` variable defined in that CI job:

    ```yaml
    .test_X_Y:
      variables:
        CI_PASS: "true"
    ```

8. Investigate each failure, determine the root cause (if you can), and file additional issues.
   The source of the failure may lie with a package dependency or with Julia itself.
   Create issues on these upstream repos, and be sure to reference them in the internal issues you created in step-5.
   If you are unable to determine the source of the failure be sure to add a comment in the internal issue outlining the steps you took to investigate the problem.

At this point all packages compatible with Julia X.Y are required to stay compatible and packages that are broken are allowed to fail.
Issues for each of these broken private packages have been created and are associated with the milestone "Julia X.Y" which allows us to determine what work we have to do if we choose to proceed with the next phase.


## Update package compatibility

At this phase we must decide if we want to use this version with EIS.
Usually we choose to use the current Julia [LTS](https://julialang.org/blog/2019/08/release-process/) but we may choose to use another release of Julia if we feel like it has an important feature (Julia 1.3 for example supported threading).

1. Update the description of the "Julia X.Y" milestone with the motivation for switching EIS to this version.
2. Communicate the intent to update the default version of Julia with all impacted teams (e.g. development/research).
   Message the impacted teams in their respective Slack channels being sure to:
   - Encourage all Julia users to install Julia X.Y, and offer assistance if needed
   - Mention any expected impact this change will have
3. Resolve all the issues attached to the "Julia X.Y" milestone, making sure to remove any `allow_failure` exceptions added to the package's `.gitlab-ci.yml` during [auditing](#audit-package-compatibility).
4. Audit all packages and switch any that are overriding the default tests to the new Julia version.

All Julia packages should now be compatible with Julia X.Y and all future changes will maintain compatibility.

## Update EIS

Now that all that our packages are compatible with Julia X.Y we can finally update EIS.
Note that we should only update the EIS to use official releases and avoid using release candidates of Julia in production.

1. Update the [Project.toml](https://gitlab.invenia.ca/invenia/eis/-/blob/master/docker/build/Project.toml) of EIS to require a minimum version of X.Y: `julia = "X.Y"`
1. Update the [Project.toml](https://gitlab.invenia.ca/invenia/eis/-/blob/master/docker/build/Project.toml) of EIS to drop package dependency versions which do not support Julia X.Y
1. Update the `FROM` image in the [Dockerfile](https://gitlab.invenia.ca/invenia/eis/-/blob/master/Dockerfile) of EIS to use Julia X.Y
1. Update the [Manifest.toml](https://gitlab.invenia.ca/invenia/eis/-/blob/master/docker/build/Manifest.toml) of EIS by the [updating production guide](https://gitlab.invenia.ca/invenia/eis/-/blob/master/docs/updating-prod.md#updating-julia-packages).
1. Submit a merge request with these changes and associate it with the "Julia X.Y" milestone
1. Communicate that EIS will be switching to Julia X.Y to all impacted teams.
1. Remove older Julia versions from the default job matrix. \
  Create, and merge, a MR which changes [/gen/julia-prefix.yml] by updating the global `julia` variable at the top of the file and removes any version before X.Y. \
  Update the `DEPRECATION_VERSION` to X.Y \
  Re-generate "templates/julia.yml" by running `julia gen/julia-template.jl > templates/julia.yml`.
1. Update `JULIA_VERSION` to X.Y for the `.coverage` and `.documentation` jobs found in [/templates/hidden-jobs.yml].
1. Additionally, any CI jobs or hidden jobs that references Julia version before X.Y should also be removed from `gitlab-ci-helper` but only if X.Y is a LTS release. \
  Note we typically only update `julia` compat entries for packages when a change to the package requires so.

Once the EIS merge request has been merged and eventually deployed to production we've completed the switch.
By staying on a supported version of Julia we ensure we can get support for any Julia failures we see in production.


[/templates/hidden-jobs.yml]: /templates/hidden-jobs.yml
[/templates/julia.yml]: /templates/julia.yml
[.gitlab-ci.yml]: .gitlab-ci.yml
[nightly CI runs]: https://gitlab.invenia.ca/invenia/wiki/-/blob/master/dev/nightly.md
