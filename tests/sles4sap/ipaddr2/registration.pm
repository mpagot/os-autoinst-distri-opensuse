# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# Summary: Registration SUT
# Maintainer: QE-SAP <qe-sap@suse.de>

use strict;
use warnings;
use Mojo::Base 'publiccloud::basetest';
use testapi;
use serial_terminal qw( select_serial_terminal );
use publiccloud::utils;
use sles4sap::ipaddr2 qw(
  ipaddr2_deployment_logs
  ipaddr2_cloudinit_logs
  ipaddr2_network_peering_clean
  ipaddr2_infra_destroy
  ipaddr2_registration
  ipaddr2_register_addons
  ipaddr2_bastion_pubip
);

sub run {
    my ($self) = @_;

    select_serial_terminal;

    my $bastion_pubip = ipaddr2_bastion_pubip();
    ipaddr2_registration(bastion_pubip => $bastion_pubip);
    ipaddr2_register_addons(bastion_pubip => $bastion_pubip);
}

sub test_flags {
    return {fatal => 1, publiccloud_multi_module => 1};
}

sub post_fail_hook {
    my ($self) = shift;
    ipaddr2_deployment_logs() if check_var('IPADDR2_DIAGNOSTIC', 1);
    ipaddr2_cloudinit_logs() unless check_var('IPADDR2_CLOUDINIT', 0);
    if (my $ibsm_rg = get_var('IBSM_RG')) {
        ipaddr2_network_peering_clean(ibsm_rg => $ibsm_rg);
    }
    ipaddr2_infra_destroy();
    $self->SUPER::post_fail_hook;
}

1;
