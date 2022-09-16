# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# Summary: Test for qe-sap-deployment
# Maintainer: QE-SAP <qe-sap@suse.de>, Michele Pagot <michele.pagot@suse.com>

use strict;
use warnings;
use Mojo::Base 'publiccloud::basetest';
use testapi;
use qesapdeployment;

use constant GIT_CLONE_LOG => '/tmp/git_clone.log';

sub run {
    my ($self) = @_;
    $self->select_serial_terminal;

    my $ansible_args = '-i /root/qe-sap-deployment/terraform/azure/inventory.yaml ' .
      '-u cloudadmin -b --become-user=root';
    assert_script_run('ansible all ' . $ansible_args . ' -a "pwd"');
    assert_script_run('ansible all ' . $ansible_args . ' -a "uname -a"');
    assert_script_run('ansible all ' . $ansible_args . ' -a "cat /etc/os-release"');
    assert_script_run('ansible hana ' . $ansible_args . ' -a "ls -lai /hana/"');
    assert_script_run('ansible vmhana01 ' . $ansible_args . ' -a "crm status"');
}

sub post_fail_hook {
    my ($self) = shift;
    $self->select_serial_terminal;
    $self->qesap_upload_logs('/root/test/qe-sap-deployment', 1);

    assert_script_run('./destroy.sh -k /root/.ssh/id_rsa', (15 * 60));
    $self->SUPER::post_fail_hook;
}

1;
