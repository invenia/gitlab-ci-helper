GitLab CI for Lab Repos
============================

Lab Repos have become a common part of the [research workflow](https://gitlab.invenia.ca/invenia/wiki/-/blob/master/research/workflow.md) both in squads and independent projects.
In some projects, it is important to provide certain guarantees about the structure of the repository and its contents.

For example, [BackrunLab](https://gitlab.invenia.ca/invenia/research/BackrunLab) requires that each leaf-directory contains a `Project.toml`, `Manifest.toml`, `backrun.jl`, and a `README.md` so that the context of the backrun can be understood and the results reproduced.

Other projects, such as [AutoregressiveLab](https://gitlab.invenia.ca/invenia/research/AutoregressiveLab), require that every experiment can be independently reproduced. 
In order to achieve that, we want each leaf-directory to contain the `Project.toml`, `Manifest.toml`, and `README.md` files like before, but also stipulate that no code is shared between experiments. 
This is because shared utilities are liable to become incompatible with one or more of the experiments over time.

For that reason, Lab Repos can set up a CI pipeline, just like a package, to check that the needs of that project are met, and provide guarantees, now and into the future, about the reproducibilty of the projects findings.

A [Lab Repo CI template](https://gitlab.invenia.ca/invenia/gitlab-ci-helper/-/tree/master/examples/labrepo.yml) can be found in the `examples` directory.

