# SUSE's openQA tests
#
# Copyright 2017-2020 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Summary: Functions to use qe-sap-deployment project
# Maintainer: QE-SAP <qe-sap@suse.de>

## no critic (RequireFilenameMatchesPackage);

=encoding utf8

=head1 NAME

qe-sap-deployment test lib

=head1 COPYRIGHT

Copyright 2017-2020 SUSE LLC
SPDX-License-Identifier: FSFAP

=head1 AUTHORS

QE SAP <qe-sap@suse.de>

=cut

package qesapdeployment;

use strict;
use warnings;
use testapi;
use mmapi 'get_current_job_id';
use utils qw(file_content_replace);
use Exporter 'import';

our @EXPORT = qw(
  get_resource_group
  configure_tfvar
  configure_variables
  configure_hanamedia
  deploy
  upload_deploy_logs
);

# Exported constants
use constant VM_USER => 'cloudadmin';
use constant SSH_KEY => '/root/.ssh/id_rsa';

# Lib internal constants

# Terraform requirement
#  terraform/azure/infrastructure.tf  "azurerm_storage_account" "mytfstorageacc"
# stdiag<PREFID><JOB_ID> can only consist of lowercase letters and numbers,
# and must be between 3 and 24 characters long
use constant QESAPDEPLOY_PREFIX => 'qesapdep';


=head1 DESCRIPTION 

Package with common methods and default or constant  values for Trento tests

=head2 Methods

=head3 get_resource_group

Return a string to be used as cloud resource group.
It contains the JobId
=cut

sub get_resource_group {
    my $job_id = get_current_job_id();
    return QESAPDEPLOY_PREFIX . "rg$job_id";
}

=head3 configure_tfvar

Generate a terraform.tfvars from a template.

=over 2

=item B<QESAPREPO> - String path of the local clone of qe-sap-deployment

=item B<PROVIDER> - cloud provider, used to select
                    the right folder in the qe-sap-deploy repo

=item B<REGION> - cloud region where to perform the deployment.
                  Used for %REGION%

=item B<OS_VERSION> - string for the OS version to be used for the deployed machine.
                      Used for %OSVER%

=back
=cut

sub configure_tfvar {
    my ($self, $qesaprepo, $provider, $region, $os_version) = @_;
    my $tfvar = $qesaprepo . '/terraform/' . lc($provider) . '/terraform.tfvars';
    assert_script_run("cp $tfvar.openqa $tfvar");
    file_content_replace($tfvar,
        q(%REGION%) => $region,
        q(%DEPLOYMENTNAME%) => get_resource_group(),
        q(%OSVER%) => $os_version,
        q(%SSHKEY%) => "/root/.ssh/id_rsa.pub"
    );
    upload_logs($tfvar);
}

=head3 configure_variables

Generate the variables.sh loaded by build.sh and destroy.sh

=over 2

=item B<QESAPREPO> - String path of the local clone of qe-sap-deployment

=item B<PROVIDER> - cloud provider, used to select
                    the right folder in the qe-sap-deploy repo

=item B<SAP_REGCODE> - SCC code

=back
=cut

sub configure_variables {
    my ($self, $qesaprepo, $provider, $sap_regcode) = @_;

    # variables.sh file
    enter_cmd 'echo "PROVIDER=' . lc($provider) . '" > variables.sh';
    enter_cmd "echo \"REG_CODE='$sap_regcode'\" >> $qesaprepo/variables.sh";
    enter_cmd "echo \"EMAIL='testing\@suse.com'\" >> $qesaprepo/variables.sh";
    enter_cmd "echo \"SAPCONF='true'\" >> $qesaprepo/variables.sh";
    enter_cmd "echo \"export REG_CODE EMAIL SAPCONF\" >> $qesaprepo/variables.sh";
    upload_logs("$qesaprepo/variables.sh");
}

=head3 configure_hanamedia

Generate the hana_media.yaml for Ansible

=over 2

=item B<QESAPREPO> - String path of the local clone of qe-sap-deployment

=item B<SAPCAR> - blob server url for the SAPCAR

=item B<IMDB_SERVER> - blob server url for the IMDB_SERVER

=item B<IMDB_CLIENT> - blob server url for the IMDB_CLIENT

=back
=cut

sub configure_hanamedia {
    my ($self, $qesaprepo, $sapcar, $imbd_server, $imbd_cient) = @_;
    my $media_var = $qesaprepo . '/ansible/playbooks/vars/azure_hana_media.yaml';
    assert_script_run("cp $media_var.openqa $media_var");
    file_content_replace($media_var,
        q(%SAPCAR%) => $sapcar,
        q(%IMDB_SERVER%) => $imbd_server,
        q(%IMDB_CLIENT%) => $imbd_cient);
}

=head3 deploy

Call build.sh and publish all the logs

=over 2

=item B<QESAPREPO> - String path of the local clone of qe-sap-deployment

=back
=cut

sub deploy {
    my ($self, $qesaprepo) = @_;

    enter_cmd 'cd ' . $qesaprepo;
    my $cmd = 'set -o pipefail ;' .
      ' ./build.sh -q -k ~/.ssh/id_rsa ' .
      '| tee build.log.txt';
    assert_script_run($cmd, (30 * 60));

    upload_deploy_logs($qesaprepo, 0);
}

=head3 upload_deploy_logs

Call build.sh and publish all the logs

=over 2

=item B<QESAPREPO> - String path of the local clone of qe-sap-deployment

=item B<FAILOK> - used as failok for the upload_logs

=back
=cut

sub upload_deploy_logs {
    my ($self, $qesaprepo, $failok) = @_;

    enter_cmd 'cd ' . $qesaprepo;

    my @logs = qw(
      build.log.txt
      terraform.init.log.txt
      terraform.plan.log.txt
      terraform.apply.log.txt
      ansible.build.log.txt
    );
    foreach my $log (@logs) {
        upload_logs($log, failok => $failok);
    }
}

1;
