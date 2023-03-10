#!/bin/bash

set -e  # Abort when a command fails

# Load common functions
common="$(dirname $0)/../functions/common"
source $common

function testsuite {
    local magenta='\033[35m'
    local reset='\033[0m'
    echo -e "${magenta}Test suite: ${@}${reset}" >&2
}

function warn() {
    local red='\033[31m'
    local reset='\033[0m'
    echo -e "${red}${@}${reset}" >&2
}

function testcase() {
    local expr="$1"
    local a=""
    local b=""

    OPS=('==' '!=' '=~')
    for op in "${OPS[@]}"; do
        if [[ "$expr" == *" $op "* ]]; then
            cond=$(echo "$expr" | sed 's/^\[\[ //' | sed 's/ \]\]$//')
            a=$(echo "$cond" | sed "s/ $op .*//")
            b=$(echo "$cond" | sed "s/.* $op //")
            break
        fi
    done

    local rc
    echo "$expr" >&2
    eval "$expr" && rc=$? || rc=$?  # Never fail even with `set -e`

    if [ $rc -eq 0 ]; then
        return 0
    else
        warn "Test failed: ($rc)"

        if [ -n "$a" ]; then
            warn "  Expression: [[ $a $op $b ]]"

            # The evaluated form won't actually run but gives enough context
            x=$(eval "echo \"$a\"" || true)
            y=$(eval "echo \"$b\"" || true)
            warn "   Evaluated: [[ $x $op $y ]]"
        else
            warn "  Expression: $expr"
        fi

        return 1
    fi
}

function reset_installers() {
    unset REFRESHED_PKGS INSTALLED_PYTHON INSTALLED_AWSCLI INSTALLED_CLOUDSPY INSTALLED_PRIVATE_PYPI_CREDS INSTALLED_AURORA_DSN
}

testsuite "refresh_pkgs"
reset_installers
refresh_pkgs
testcase '$REFRESHED_PKGS == true'
testcase '[[ -z "$(refresh_pkgs 2>&1)" ]]'


testsuite "package_install"
reset_installers
pkg="htop"  # Using an application that shouldn't be used by our CI jobs to avoid interferrence on shared runners
# Need to remove package if it is already installed so that we actually test 'package_install' works
if [[ -x "$(command -v $pkg)" ]] ; then
    if [[ -x "$(command -v yum)" ]] ; then
        echo_eval ${SUDO} yum remove -y $pkg
    elif [[ -x "$(command -v apt-get)" ]] ; then
        echo_eval ${SUDO} apt-get remove -y $pkg
        echo_eval hash -r
    elif [[ -x "$(command -v brew)" ]] ; then
        echo_eval brew uninstall $pkg && brew cleanup $pkg
    fi
fi
testcase '[[ ! -x "$(command -v '$pkg')" ]]'  # Package is not installed
package_install $pkg
testcase '[[ -x "$(command -v '$pkg')" ]]'  # Package is installed


testsuite "install_python"
reset_installers
# Need to remove python3 if it's installed so that the 'install_python' command does all the tests
if [[ -x "$(command -v python3)" ]] ; then
    if [[ -x "$(command -v yum)" ]] ; then
        echo_eval ${SUDO} yum remove -y python3
    elif [[ -x "$(command -v apt-get)" ]] ; then
        echo_eval ${SUDO} apt-get remove -y python3 python3-venv python3-minimal
        echo_eval hash -r
    fi
fi
install_python
testcase '[[ $REFRESHED_PKGS == true ]]'
testcase '[[ $INSTALLED_PYTHON == true ]]'
testcase '[[ "$(python --version 2>&1)" =~ ^Python\ 3 ]]'
testcase '[[ "$(pip --version)" =~ \(python\ 3.[0-9]+\)$ ]]'
testcase '[[ -z "$(install_python 2>&1)" ]]'

testsuite "eval_echo"
test_code="
import datetime

print(datetime.datetime.now())
print('this has single quotes in it')
print(\\\"this is a double quote inside a quote\\\")
"
result=$(echo_eval 'echo "$test_code"')
# NOTE: Need to use '"'"' = ' if we want to use single quotes inside of a singly quoted string
# Test new lines still exist
testcase '[[ "$result" == *$'"'"'\n'"'"'* ]]'
# Test single quotes still exist
testcase '[[ "$result" == *$"'"'"'"* ]]'
# Test double quotes still exist
testcase '[[ "$result" == *$'"'"'"'"'"'* ]]'

testsuite "enter_python_venv"
reset_installers
[[ -n "$VIRTUAL_ENV" ]] && deactivate
enter_python_venv
testcase '[[ $INSTALLED_PYTHON == true ]]'
testcase '[[ -d ./venv ]]'
testcase '[[ -n "$VIRTUAL_ENV" ]]'
deactivate
testcase '[[ -z "$VIRTUAL_ENV" ]]'

testsuite "enter_python_venv other"
reset_installers
enter_python_venv other
testcase '[[ $INSTALLED_PYTHON == true ]]'
testcase '[[ -d ./other ]]'
testcase '[[ -n "$VIRTUAL_ENV" ]]'
enter_python_venv
testcase '[[ $VIRTUAL_ENV == $(pwd)/other ]]'
enter_python_venv

deactivate
testcase '[[ -z "$VIRTUAL_ENV" ]]'

testsuite "enter_python_venv hidden"
reset_installers
enter_python_venv hidden
deactivate
testcase '! within_venv'
export PATH="$(pwd)/hidden/bin:$PATH"
testcase 'within_venv'
testcase '[[ -z "$VIRTUAL_ENV" ]]'
testcase '[[ $(command -v python) == "$(pwd)/hidden/bin/python" ]]'
enter_python_venv
testcase '[[ $(command -v python) == "$(pwd)/hidden/bin/python" ]]'
export PATH=${PATH#$(pwd)/hidden/bin:}

testsuite "install_awscli"
reset_installers
echo_eval install_awscli
testcase '[[ $INSTALLED_PYTHON == true ]]'
testcase '[[ $INSTALLED_AWSCLI == true ]]'
testcase '[[ -x "$(command -v aws)" ]]'
testcase '[[ -z "$(install_awscli 2>&1)" ]]'

testsuite "install_private_pypi_creds"
reset_installers
echo_eval install_private_pypi_creds
testcase '[[ $INSTALLED_PYTHON == true ]]'
testcase '[[ $INSTALLED_PRIVATE_PYPI_CREDS == true ]]'
testcase '[[ -d ~/.pip ]]'
testcase '[[ -f ~/.pip/pip.conf ]]'
testcase '[[ -f ~/.pypirc ]]'

testsuite "install_cloudspy"
reset_installers
echo_eval install_cloudspy
testcase '[[ $REFRESHED_PKGS == true ]]'
testcase '[[ $INSTALLED_PYTHON == true ]]'
testcase '[[ $INSTALLED_PRIVATE_PYPI_CREDS == true ]]'
testcase '[[ $INSTALLED_CLOUDSPY == true ]]'
testcase '[[ -x "$(command -v aws)" ]]'
testcase '[[ -z "$(install_cloudspy 2>&1)" ]]'


testsuite "stack_name"
testcase '! stack_name'

COMMIT_REF_SLUG=$CI_COMMIT_REF_SLUG
DEFAULT_BRANCH=$CI_DEFAULT_BRANCH
PIPELINE_ID=$CI_PIPELINE_ID

CI_PIPELINE_ID=0
CI_DEFAULT_BRANCH=main

# Add CI_PIPELINE_ID when ref is default branch
CI_COMMIT_REF_SLUG=main
testcase '[[ $(stack_name prefix) == prefix-main-0 ]]'

# Otherwise don't add CI_PIPELINE_ID
CI_COMMIT_REF_SLUG=master
testcase '[[ $(stack_name prefix) == prefix-master ]]'
CI_COMMIT_REF_SLUG=a/b/c
testcase '[[ $(stack_name no-slash) == no-slash-a-b-c ]]'

# Testing for variable truncate
CI_COMMIT_REF_SLUG=master
testcase '[[ $(stack_name prefix 8) == prefix-m ]]'

# Testing for hash
testcase '[[ $(stack_name prefix 8 3) == pref-d50 ]]'

CI_COMMIT_REF_SLUG=$COMMIT_REF_SLUG
CI_DEFAULT_BRANCH=$DEFAULT_BRANCH
CI_PIPELINE_ID=$PIPELINE_ID


testsuite "aws_account_id"
testcase '[[ $(aws_account_id) =~ ^[0-9]{12}$ ]]'

# Note: Due to using a subshell to capture the stderr the installer state variable will
# only exist inside of the subshell. We need to perform a call in the shell directly so
# that the state variable is correctly set.
reset_installers
testcase '[[ -n $(aws_account_id 2>&1 >/dev/null) ]]'  # Installer runs
aws_account_id &> /dev/null  # Set state outside of a subshell
testcase '[[ -z $(aws_account_id 2>&1 >/dev/null) ]]'  # Installer has already ran

testsuite "aws_region"
testcase '[[ $(aws_region) =~ ^us-[a-z]*-[0-9]{1}$ ]]' # Example aws region format: us-east-1

testsuite "assume_test_role / unassume_test_role"
name=$(stack_name $STACK_NAME_PREFIX)
role_name=${name}-TestRole

# Role required when STACK_NAME is not specified
testcase '! assume_test_role'

# Full ARN
testsuite "Full ARN"
assume_test_role arn:aws:iam::$(aws_account_id):role/$role_name
testcase '[[ $(aws sts get-caller-identity --query Arn --output text) == *test-${CI_PIPELINE_ID} ]]'

# Unassume test role
testsuite "Unassume test role"
unassume_test_role
testcase '[[ $(aws sts get-caller-identity --query Arn --output text) != *test-${CI_PIPELINE_ID} ]]'

# Role name
testsuite "Role name"
assume_test_role $role_name
testcase '[[ $(aws sts get-caller-identity --query Arn --output text) == *test-${CI_PIPELINE_ID} ]]'
unassume_test_role

# Role name and options
testsuite "Role name and options"
assume_test_role $role_name --duration 3600
testcase '[[ $(aws sts get-caller-identity --query Arn --output text) == *test-${CI_PIPELINE_ID} ]]'
unassume_test_role

# Assume role based upon STACK_NAME
testsuite "Assume role based upon STACK_NAME"
STACK_NAME=$name assume_test_role
testcase '[[ $(aws sts get-caller-identity --query Arn --output text) == *test-${CI_PIPELINE_ID} ]]'
unassume_test_role

# STACK_NAME and options
testsuite "STACK_NAME and options"
STACK_NAME=$name assume_test_role --duration 3600
testcase '[[ $(aws sts get-caller-identity --query Arn --output text) == *test-${CI_PIPELINE_ID} ]]'
unassume_test_role


testsuite "stack_status"
STACK_NAME=$(stack_name $STACK_NAME_PREFIX)
assume_test_role
testcase '[[ $(stack_status $STACK_NAME) =~ (CREATE|UPDATE)_COMPLETE ]]'
testcase '! stack_status _ 2> /dev/null'  # Note: Using invalid stack name
unassume_test_role


testsuite "stack_exists"
STACK_NAME=$(stack_name $STACK_NAME_PREFIX)
assume_test_role
testcase 'stack_exists $STACK_NAME'
testcase '! stack_exists _'  # Note: Using invalid stack name
unassume_test_role


testsuite "Central EISDB"
reset_installers
assume_test_role
install_aurora_credentials
testcase '[[ $INSTALLED_AURORA_CREDENTIALS == true ]]'
testcase '[[ -f $PGPASSFILE ]]'
testcase '[[ -n $AURORA_READER_ENDPOINT ]]'
testcase '[[ -n $AURORA_DATABASE ]]'
testcase '[[ -n $AURORA_USER ]]'
testcase '[[ -n $AURORA_PORT ]]'
unassume_test_role

testsuite "benchmark reports"
mkdir -p tmp_stats
echo '{"stat.median_time": 6e10, "stat.minimum_time": 3e10, "stat.median_memory": 1024 }' > tmp_stats/my_stats.json
rescaled=$(rescale_json_values tmp_stats/my_stats.json m KiB)
testcase '[[ $rescaled == *"\"stat.median_memory(KiB)\": 1"* ]]'
testcase '[[ $rescaled == *"\"stat.median_time(m)\": 1"* ]]'
testcase '[[ $rescaled == *"\"stat.minimum_time(m)\": 0.5"* ]]'

format_benchmark_reports tmp_stats/my_stats.json metrics
testcase ' [[ -f "tmp_stats/performance.json" ]]'
testcase '[[ -f "tmp_stats/metrics.txt" ]]'
rm -rf tmp_stats

testsuite "validate_tag"
testcase 'validate_tag 1.2.3'
testcase 'validate_tag 1.2.3-rc'
testcase 'validate_tag 1.2.3-ab1'
testcase 'validate_tag 1.2.3-ab-xy1'
testcase 'validate_tag 1.0.0-alpha'
testcase 'validate_tag 1.0.0-alpha.1'
testcase 'validate_tag 1.0.0-0.3.7'
testcase 'validate_tag 1.0.0-x.7.z.92'
testcase 'validate_tag 1.0.0-x-y-z.-.1'
testcase '! validate_tag 1.2'        # missing patch version
testcase '! validate_tag 1.2-rc'     # missing patch version

testsuite "get_major_version"
testcase '[[ $(get_major_version 1.2.3) == 1 ]]'
testcase '[[ $(get_major_version 1.2.3-4.5.6) == 1 ]]'

testsuite "get_minor_version"
testcase '[[ $(get_minor_version 1.2.3) == 2 ]]'
testcase '[[ $(get_minor_version 1.2.3-4.5.6) == 2 ]]'

testsuite "get_patch_version"
testcase '[[ $(get_patch_version 1.2.3) == 3 ]]'
testcase '[[ $(get_patch_version 1.2.33) == 33 ]]'
testcase '[[ $(get_patch_version 1.2.33-rc) == 33 ]]'
testcase '[[ $(get_patch_version 1.2.3-4.5.6) == 3 ]]'

testsuite "get_version_type"
testcase '[[ $(get_version_type 1.0.0) == major ]]'
testcase '[[ $(get_version_type 1.2.0) == minor ]]'
testcase '[[ $(get_version_type 1.2.3) == patch ]]'

testsuite "bump_major_version"
testcase '[[ $(bump_major_version 1.0.0) == 2.0.0 ]]'
testcase '[[ $(bump_major_version 1.2.0) == 2.0.0 ]]'
testcase '[[ $(bump_major_version 1.2.3) == 2.0.0 ]]'

testsuite "bump_minor_version"
testcase '[[ $(bump_minor_version 1.0.0) == 1.1.0 ]]'
testcase '[[ $(bump_minor_version 1.1.0) == 1.2.0 ]]'
testcase '[[ $(bump_minor_version 1.2.3) == 1.3.0 ]]'

testsuite "bump_patch_version"
testcase '[[ $(bump_patch_version 1.0.0) == 1.0.1 ]]'
testcase '[[ $(bump_patch_version 1.1.1) == 1.1.2 ]]'
testcase '[[ $(bump_patch_version 1.1.2) == 1.1.3 ]]'

testsuite "create_release_candidate"
testcase '[[ $(create_release_candidate 1.2.3 version::external) == 2.0.0-rc ]]'
testcase '[[ $(create_release_candidate 1.2.3 version::internal) == 1.3.0-rc ]]'
testcase '[[ $(create_release_candidate 1.2.3 version::bugfix) == 1.2.4-rc && $? = 2 ]]'
testcase '[[ $(create_release_candidate 1.2.3 "foo bar version::bugfix") == 1.2.4-rc ]]'
testcase '[[ $(create_release_candidate 1.2.3-rc version::external) == 2.0.0-rc ]]'
testcase '[[ $(create_release_candidate 1.2.3-rc version::internal) == 1.3.0-rc ]]'
testcase '[[ $(create_release_candidate 1.2.3-rc version::bugfix) == 1.2.4-rc && $? = 2 ]]'
testcase '[[ $(create_release_candidate 1.2.3-rc "foo bar version::bugfix") == 1.2.4-rc ]]'
testcase '[[ $(create_release_candidate 11.22.33 version::bugfix) == 11.22.34-rc ]]'
testcase '! create_release_candidate 1.2 version::external'  # bad tag
testcase '! create_release_candidate 1.2.3 version::major'  # bad label
