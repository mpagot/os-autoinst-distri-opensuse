# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# Summary: Test for qe-sap-deployment
# Maintainer: QE-SAP <qe-sap@suse.de>, Michele Pagot <michele.pagot@suse.com>

use strict;
use warnings;
use Mojo::Base 'publiccloud::basetest';
use testapi;
use qesapdeployment;

sub run {
    my ($self) = @_;
    $self->select_serial_terminal;

    qesap_deploy('/root/.ssh/id_rsa');
}

sub post_fail_hook {
    my ($self) = shift;
    $self->select_serial_terminal;
    qesap_upload_logs('/root/test/qe-sap-deployment', 1);

    assert_script_run('./destroy.sh -k /root/.ssh/id_rsa', (15 * 60));
    $self->SUPER::post_fail_hook;
}

1;
