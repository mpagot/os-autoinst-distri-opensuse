# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# Summary: Trento test
# Maintainer: QE-SAP <qe-sap@suse.de>, Michele Pagot <michele.pagot@suse.com>

use strict;
use warnings;
use Mojo::Base 'publiccloud::basetest';
use base 'consoletest';
use strict;
use testapi;
use base 'trento';

use constant TRENTO_AZ_PREFIX => 'openqa-trento';
use constant TRENTO_AZ_ACR_PREFIX => 'openqatrentoacr';

sub run {
    my ($self) = @_;
    $self->select_serial_terminal;

    ######################
    # az login
    set_var 'PUBLIC_CLOUD_PROVIDER' => 'AZURE';
    my $provider = $self->provider_factory();
    script_run('az group list --query "[].name" -o tsv');
    assert_script_run('for g in $(for l in $(az acr list --query "[].loginServer" -o tsv | grep ' . TRENTO_AZ_ACR_PREFIX . '); do az acr show --name ${l} --query resourceGroup -o tsv; done); do az group delete --name ${g} -y; done', 3600);
    assert_script_run('az group list --query "[].name" -o tsv | grep ' . TRENTO_AZ_PREFIX . '|| echo "No trento Azure resources groups"', 360);
    assert_script_run('for g in $(az group list --query "[].name" -o tsv | grep ' . TRENTO_AZ_PREFIX . '); do az group delete --name ${g} -y; done', 1800);
}

1;
