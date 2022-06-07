# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# Summary: Trento test
# Maintainer: QE-SAP <qe-sap@suse.de>, Michele Pagot <michele.pagot@suse.com>

use Mojo::Base 'publiccloud::basetest';
use base 'consoletest';
use strict;
use testapi;
use utils qw(script_retry);
use base 'trento';


sub run {
    my ($self) = @_;
    die "Only AZURE deployment supported for the moment" unless check_var('PUBLIC_CLOUD_PROVIDER', 'AZURE');
    $self->select_serial_terminal;

    my $resource_group = $self->get_resource_group;

    # check if VM is still there :-)
    assert_script_run("az vm list -g $resource_group --query \"[].name\"  -o tsv", 180);

    # get deployed version from the cluster
    my $machine_ip = $self->az_get_vm_ip;
    my $kubectl_pods = script_output($self->az_vm_ssh_cmd('kubectl get pods', $machine_ip), 180);
    foreach my $row (split(/\n/, $kubectl_pods)) {
        if ($row =~ m/trento-server-web/) {
            my $pod_name = (split /\s/, $row)[0];
            my $trento_ver_cmd = $self->az_vm_ssh_cmd("kubectl exec --stdin $pod_name -- /app/bin/trento version", $machine_ip);
            script_run($trento_ver_cmd, 180);
        }
    }

    # test if the web page is reachable on http
    my $trento_url = 'http://' . $machine_ip . '/';
    script_run('curl --version');
    assert_script_run('curl -k  ' . $trento_url);
    # HEAD request
    my $trento_http_code = script_output('curl -I --silent --output /dev/null --write-out "%{http_code}" ' . $trento_url);
    # HEAD request and follow redirection
    my $curl_cmd_test = 'test $(' .
      'curl -I -L --silent --output /dev/null --write-out "%{http_code}" ' . $trento_url .
      ') -eq 200 ';
    script_retry($curl_cmd_test, retry => 5, delay => 60);

    # only available from curl 7.76.0 (and for the moment we have 7.66)
    #assert_script_run('curl -k  ' . $trento_url . ' --fail-with-body');
}

sub post_fail_hook {
    my ($self) = @_;
    $self->k8s_logs(('web', 'runner'));

    $self->az_delete_group;
    $self->SUPER::post_fail_hook;
}

1;
