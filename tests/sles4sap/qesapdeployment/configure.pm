# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# Summary: Configuration steps for qe-sap-deployment
# Maintainer: QE-SAP <qe-sap@suse.de>, Michele Pagot <michele.pagot@suse.com>

use strict;
use warnings;
use Mojo::Base 'publiccloud::basetest';
use testapi;
use mmapi 'get_current_job_id';
use qesapdeployment;

sub run {
    my ($self) = @_;
    $self->select_serial_terminal;

    # Init al the PC gears (ssh keys)
    my $provider = $self->provider_factory();

    # tfvars file
    my $qesap_provider = $self->qesap_translate_provider_name();

    qesap_configure_tfvar($qesap_provider,
        $provider->provider_client->region,
        'qesapdep' . get_current_job_id(),
        get_required_var('QESAPDEPLOY_OS_VER'),
        '/root/.ssh/id_rsa.pub');

    # variables.sh file
    qesap_configure_variables($qesap_provider,
        get_required_var('SCC_REGCODE_SLES4SAP'));

    # Ansible blob file
    qesap_configure_hanamedia(get_var('QESAPDEPLOY_SAPCAR'),
        get_var('QESAPDEPLOY_IMDB_SERVER'),
        get_var('QESAPDEPLOY_IMDB_CLIENT'));
}

sub post_fail_hook {
    my ($self) = shift;
    $self->select_serial_terminal;
    qesap_upload_logs('', 1);
    $self->SUPER::post_fail_hook;
}

1;
