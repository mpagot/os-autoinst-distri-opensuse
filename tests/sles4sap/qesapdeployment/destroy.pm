# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# Summary: Test for qe-sap-deployment
# Maintainer: QE-SAP <qe-sap@suse.de>, Michele Pagot <michele.pagot@suse.com>

use strict;
use warnings;
use Mojo::Base 'publiccloud::basetest';
use testapi;
use base 'qesapdeployment';

sub run {
    my ($self) = @_;
    $self->select_serial_terminal;

    $self->qesap_destroy();
}

sub post_fail_hook {
    my ($self) = shift;
    $self->select_serial_terminal;
    enter_cmd 'cd ~/test/qe-sap-deployment';
    upload_logs('terraform.init.log.txt', failok => 1);
    upload_logs('terraform.plan.log.txt', failok => 1);
    upload_logs('terraform.apply.log.txt', failok => 1);
    upload_logs('terraform.destroy.log.txt', failok => 1);
    upload_logs('destroy.log.txt', failok => 1);
    upload_logs('ansible.build.log.txt', failok => 1);
    upload_logs('ansible.destroy.log.txt', failok => 1);

    assert_script_run('./destroy.sh -k ~/.ssh/id_rsa', (15 * 60));
    $self->SUPER::post_fail_hook;
}

1;
