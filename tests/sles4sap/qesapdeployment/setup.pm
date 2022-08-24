# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# Summary: Setup and install more tools in the running jumphost image for qe-sap-deployment
# Maintainer: QE-SAP <qe-sap@suse.de>, Michele Pagot <michele.pagot@suse.com>

use strict;
use warnings;
use Mojo::Base 'publiccloud::basetest';
use base 'consoletest';
use testapi;

use constant GIT_CLONE_LOG => '/tmp/git_clone.log';
use constant PIP_INSTALL_LOG => '/tmp/pip_install.log';


sub run {
    my ($self) = @_;
    $self->select_serial_terminal;

    # Install needed tools

    # If 'az' is preinstalled, we test that version
    assert_script_run('az --version');

    # Get the code for the qe-sap-deployment
    my $git_repo = get_var(QESAPDEPLOY_GITHUB_REPO => 'github.com/SUSE/qe-sap-deployment');
    my $git_clone_cmd = 'git clone https://' . $git_repo;
    my $git_branch = get_var('QESAPDEPLOY_GITHUB_BRANCH', 'main');

    enter_cmd 'mkdir ~/test && cd ~/test';
    assert_script_run("set -o pipefail ; $git_clone_cmd | tee " . GIT_CLONE_LOG);
    enter_cmd 'cd ~/test/qe-sap-deployment';
    assert_script_run("git checkout " . $git_branch);

    enter_cmd 'pip config --site set global.progress_bar off';
    my $pip_ints_cmd = 'pip install --no-color --no-cache-dir ';
    # Hack to fix an installation conflict. Someone install PyYAML 6.0 and awscli needs an older one
    assert_script_run($pip_ints_cmd . 'awscli==1.19.48 | tee ' . PIP_INSTALL_LOG, 180);
    assert_script_run($pip_ints_cmd . '-r ~/test/qe-sap-deployment/requirements.txt | tee -a ' . PIP_INSTALL_LOG, 180);

    # test ansible
    assert_script_run('ansible --version');
}

sub post_fail_hook {
    my ($self) = shift;
    $self->select_serial_terminal;
    upload_logs(GIT_CLONE_LOG);
    upload_logs(PIP_INSTALL_LOG);
    $self->SUPER::post_fail_hook;
}

1;
