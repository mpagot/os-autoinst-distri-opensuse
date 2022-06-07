# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# Summary: Trento test
# Maintainer: QE-SAP <qe-sap@suse.de>, Michele Pagot <michele.pagot@suse.com>

use Mojo::Base 'publiccloud::basetest';
use base 'consoletest';
use strict;
use testapi;
use base 'trento';

sub run {
    my ($self) = @_;
    die "Only AZURE deployment supported for the moment" unless check_var('PUBLIC_CLOUD_PROVIDER', 'AZURE');
    $self->select_serial_terminal;

    my $resource_group = $self->get_resource_group;
    my $machine_name = $self->get_vm_name;
    my $acr_name = $self->get_acr_name;
    # my $openqa_ttl = get_var('MAX_JOB_TIME', 7200) + get_var('PUBLIC_CLOUD_TTL_OFFSET', 300);
    # my $created_by = get_var('PUBLIC_CLOUD_RESOURCE_NAME', 'openqa-vm');
    # my $tags = "openqa-cli-test-tag=$job_id openqa_created_by=$created_by openqa_ttl=$openqa_ttl";

    # Configure default location and create Resource group
    # assert_script_run("az configure --defaults location=southeastasia");

    enter_cmd "cd /root/test";
    ###########################
    # Run the Trento deployment
    my $vm_image = get_var('TRENTO_VM_IMAGE', 'SUSE:sles-sap-15-sp3-byos:gen2:latest');
    my $deploy_script_log = 'script_00.040.txt';
    my $deploy_script_run = './';
    $deploy_script_run = 'bash -x ';
    my $cmd_00_040 = 'set -o pipefail ; ' . $deploy_script_run . "00.040-trento_vm_server_deploy_azure.sh " .
      " -g $resource_group" .
      " -s $machine_name" .
      " -i $vm_image" .
      ' -a ' . $self->VM_USER .
      ' -k ' . $self->SSH_KEY . '.pub' .
      " -v 2>&1|tee $deploy_script_log";
    assert_script_run($cmd_00_040, 360);
    upload_logs($deploy_script_log);

    my $trento_registry_server = get_var('TRENTO_REGISTRY_SERVER', 'registry.suse.com/trento/trento-server');

    #[
    #  {
    #     "registry": "registry.suse.com/trento/trento-server",
    #     "version": "1.0.0",
    #     "type": "chart"
    #   },
    #   {
    #     "registry": "registry.suse.com/trento/trento-web",
    #     "version": "1.0.0",
    #     "type": "image"
    #   },
    #  {
    #     "registry": "registry.suse.com/trento/trento-runner",
    #     "type": "image"
    #  }
    #]
    $deploy_script_log = 'script_trento_acr_azure.log.txt';
    my $trento_acr_azure_cmd = 'set -o pipefail ; ' . $deploy_script_run . "trento_acr_azure.sh " .
      "-g $resource_group " .
      "-n $acr_name " .
      "-r $trento_registry_server " .
      "-v 2>&1|tee $deploy_script_log";
    assert_script_run($trento_acr_azure_cmd, 360);
    upload_logs($deploy_script_log);

    my $machine_ip = $self->az_get_vm_ip;
    my $acr_server = script_output("az acr list -g $resource_group --query \"[0].loginServer\" -o tsv");
    my $acr_username = script_output("az acr credential show -n $acr_name --query username -o tsv");
    my $acr_secret = script_output("az acr credential show -n $acr_name --query 'passwords[0].value' -o tsv");
    record_info('ACR credentials', "$acr_username|$acr_secret");

    # Check what registry has been created by  trento_acr_azure_cmd
    assert_script_run("az acr repository list -n $acr_name");

    $deploy_script_log = 'script_1.010.log.txt';
    #my $cmd_01_010 = './01.010-trento_server_installation_premium_v.sh '.
    my $cmd_01_010 = 'set -o pipefail ; ' . $deploy_script_run . '01.010-trento_server_installation_premium_v.sh ' .
      " -i $machine_ip " .
      ' -k ' . $self->SSH_KEY .
      ' -u ' . $self->VM_USER .
      ' -c 3.8.2 ' .
      ' -p $(pwd) ' .
      " -r $acr_server/trento/trento-server " .
      "-s $acr_username " .
      '-w $(az acr credential show -n ' . $acr_name . " --query 'passwords[0].value' -o tsv) " .
      "-v 2>&1|tee $deploy_script_log";
    assert_script_run($cmd_01_010, 600);
    upload_logs($deploy_script_log);
}

sub post_fail_hook {
    my ($self) = @_;

    $self->k8s_logs(('web', 'runner'));
    $self->az_delete_group;

    $self->SUPER::post_fail_hook;
}
1;
