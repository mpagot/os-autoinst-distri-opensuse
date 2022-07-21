# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# Summary: Test for qe-sap-deployment
# Maintainer: QE-SAP <qe-sap@suse.de>, Michele Pagot <michele.pagot@suse.com>

use strict;
use warnings;
use Mojo::Base 'publiccloud::basetest';
use base 'consoletest';
use testapi;

use constant GIT_CLONE_LOG => '/tmp/git_clone.log';

sub run {
    my ($self) = @_;
    $self->select_serial_terminal;

    # Install needed tools

    # If 'az' is preinstalled, we test that version
    assert_script_run('az --version');

    # Get the code for the qe-sap-deployment 
    my $git_repo = get_var(QESAPDEPLOY_GITHUB_REPO => 'github.com/SUSE/qe-sap-deployment');
    my $git_branch = get_var('QESAPDEPLOY_GITHUB_BRANCH', 'main');
    #my $git_token = get_var(QESAPDEPLOY_GITHUB_TOKEN => get_required_var('_SECRET_QESAPDEPLOY_GITHUB_TOKEN'));

    #my $git_clone_cmd = 'https://git:' . $git_token . '@' . $git_repo;
    my $git_clone_cmd = 'https://' . $git_repo;
    enter_cmd 'mkdir ${HOME}/test && cd ${HOME}/test';
    assert_script_run("git clone $git_clone_cmd | tee " . GIT_CLONE_LOG);
    enter_cmd 'cd qe-sap-deployment';
    assert_script_run("git checkout " . $git_branch);
    
    # prepare the python environment
    assert_script_run('python3 -m venv venv');
    assert_script_run('source venv/bin/activate');
    assert_script_run('pip install -r ${HOME}/test/qe-sap-deployment/requirements.txt'); 
    enter_cmd 'cd ${HOME}/test/qe-sap-deployment/terraform/azure';
    
    # test terraform, python and ansible
    assert_script_run('terraform init');
    assert_script_run('python3 ${HOME}/test/qe-sap-deployment/scripts/out2inventory.py --help');
    assert_script_run('ansible --version');
}

sub post_fail_hook {
    my ($self) = shift;
    # $self->select_serial_terminal;
    upload_logs(GIT_CLONE_LOG);
    $self->SUPER::post_fail_hook;
}

1;
