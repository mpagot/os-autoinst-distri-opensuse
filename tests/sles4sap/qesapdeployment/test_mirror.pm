# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# Summary: Test for qe-sap-deployment
# Maintainer: QE-SAP <qe-sap@suse.de>, Michele Pagot <michele.pagot@suse.com>

use strict;
use warnings;
use Mojo::Base 'publiccloud::basetest';
use testapi;
use qesapdeployment;
use hacluster qw($crm_mon_cmd cluster_status_matches_regex);

sub run {
    my ($self) = @_;
    my $provider_setting = get_required_var('PUBLIC_CLOUD_PROVIDER');

    if ($provider_setting eq 'AZURE') {
        if (get_var("QESAPDEPLOY_IBSMIRROR_RESOURCE_GROUP")) {
            my $rg = qesap_az_get_resource_group();
            my $ibs_mirror_rg = get_var('QESAPDEPLOY_IBSMIRROR_RESOURCE_GROUP');
            qesap_az_vnet_peering(source_group => $rg, target_group => $ibs_mirror_rg);
            qesap_add_server_to_hosts(name => 'download.suse.de', ip => get_required_var("QESAPDEPLOY_IBSMIRROR_IP"));
            qesap_az_vnet_peering_delete(source_group => $rg, target_group => $ibs_mirror_rg);
        }
    }
    elsif ($provider_setting eq 'EC2') {
        if (get_var("QESAPDEPLOY_IBSMIRROR_IP_RANGE")) {
            my $deployment_name = qesap_calculate_deployment_name('qesapval');
            my $vpc_id = qesap_aws_get_vpc_id(resource_group => $deployment_name);
            die "No vpc_id in this deployment" if $vpc_id eq 'None';
            my $ibs_mirror_target_ip = get_var('QESAPDEPLOY_IBSMIRROR_IP_RANGE');    # '10.254.254.240/28'
            die 'Error in network peering setup.' if !qesap_aws_vnet_peering(target_ip => $ibs_mirror_target_ip, vpc_id => $vpc_id);
            qesap_add_server_to_hosts(name => 'download.suse.de', ip => get_required_var("QESAPDEPLOY_IBSMIRROR_IP"));
            die 'Error in network peering delete.' if !qesap_aws_delete_transit_gateway_vpc_attachment(name => $deployment_name . '*');
        }
    }
}

sub post_fail_hook {
    my ($self) = shift;
    qesap_test_postfail(
        provider => get_required_var('PUBLIC_CLOUD_PROVIDER'),
        net_peering_is => get_var("QESAPDEPLOY_IBSMIRROR_RESOURCE_GROUP", get_var("QESAPDEPLOY_IBSMIRROR_IP_RANGE")));
    $self->SUPER::post_fail_hook;
}

1;
