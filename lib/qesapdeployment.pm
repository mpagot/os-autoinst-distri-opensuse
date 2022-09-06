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

# Constants
use constant DEPLOYMENT_DIR => get_var('DEPLOYMENT_DIR', '/root/qe-sap-deployment');
use constant QESAP_GIT_CLONE_LOG => '/tmp/git_clone.log';
use constant PIP_INSTALL_LOG => '/tmp/pip_install.log';

my @log_files = ();
my %variables = ();

our @EXPORT = qw(
  qesap_create_folder_tree
  qesap_pip_install
  qesap_upload_logs
  qesap_get_deployment_code
  get_resource_group
  qesap_configure_tfvar
  qesap_configure_variables
  qesap_configure_hanamedia
  qesap_deploy
  qesap_translate_provider_name
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

Package with common methods and default or constant  values for qe-sap-deployment

=head2 Methods
=head3 qesap_create_folder_tree

Create all needed folders

=cut

sub qesap_create_folder_tree {
  assert_script_run('mkdir -p ' . DEPLOYMENT_DIR, quiet => 1);
}

=head3 qesap_pip_install

  Install all Python requirements of the qe-sap-deployment

=cut

sub qesap_pip_install {
    enter_cmd 'pip config --site set global.progress_bar off';
    my $pip_ints_cmd = 'pip install --no-color --no-cache-dir ';
    # Hack to fix an installation conflict. Someone install PyYAML 6.0 and awscli needs an older one
    push(@log_files, PIP_INSTALL_LOG);
    assert_script_run($pip_ints_cmd . 'awscli==1.19.48 | tee ' . PIP_INSTALL_LOG, 180);
    assert_script_run($pip_ints_cmd . '-r ' . DEPLOYMENT_DIR . '/requirements.txt | tee -a ' . PIP_INSTALL_LOG, 180);
}

=head3 qesap_upload_logs

    collect and upload logs (pip, qesap, tfvars, config.yaml)

=over 2

=item B<QESAPREPO> - String path of the local clone of qe-sap-deployment

=item B<FAILOK> - used as failok for the upload_logs

=back
=cut

sub qesap_upload_logs {
    my ($self, $qesaprepo, $failok) = @_;

    if ($qesaprepo ne '') {
      # to be removed in favour of the push to @log_files approach
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
    record_info("Uploading logfiles", join("\n", @log_files));
    for my $file (@log_files) {
        upload_logs($file, failok => $failok);
    }
}

=head3 qesap_get_variables

    Create a hash of variables and a list of required vars to replace in yaml config.
    Values are taken either from ones defined in openqa ("value") or ("default") values within this function.
    Openqa value takes precedence.
=cut

sub qesap_get_variables {
    $variables{"HANA"} = get_required_var("HANA");
    $variables{"SCC_REGCODE_SLES4SAP"} = get_required_var("SCC_REGCODE_SLES4SAP");
    $variables{"EMAIL"} = get_var("EMAIL");
    $variables{"STORAGE_ACCOUNT_NAME"} = get_var("STORAGE_ACCOUNT_NAME");
    $variables{"STORAGE_ACCOUNT_KEY"} = get_var("STORAGE_ACCOUNT_KEY");
    $variables{"PUBLIC_CLOUD_RESOURCE_GROUP"} = get_var("PUBLIC_CLOUD_RESOURCE_GROUP");
    $variables{"FORCED_DEPLOY_REPO_VERSION"} = get_var("FORCED_DEPLOY_REPO_VERSION", get_var("VERSION"));
    $variables{"FORCED_DEPLOY_REPO_VERSION"} =~ s/-/_/g ;
    $variables{"FENCING_MECHANISM"} = get_var("FENCING_MECHANISM", "sbd");
    $variables{'HA_SAP_REPO'} = get_var("HA_SAP_REPO") ? get_var("HA_SAP_REPO") . "/SLE_" . $variables{FORCED_DEPLOY_REPO_VERSION}{default} : "";
}

=head3 qesap_translate_provider_name

Translate the provider name from PUBLIC_CLOUD_PROVIDER
to the string used in the qe-sap-provider code

=cut

sub qesap_translate_provider_name {
    if (get_required_var('PUBLIC_CLOUD_PROVIDER') eq 'AZURE') {
        return 'AZURE';
    }
    elsif (get_required_var('PUBLIC_CLOUD_PROVIDER') eq 'EC2') {
        return 'AWS';
    }
    elsif (get_required_var('PUBLIC_CLOUD_PROVIDER') eq 'GCE') {
        return 'GCP';
    }
    die get_required_var('PUBLIC_CLOUD_PROVIDER') . ' not supported in qe-sap-deployment';
}

=head3 qesap_get_deployment_code

Get the qe-sap-deployment code
=cut

sub qesap_get_deployment_code {
    record_info("QESAP repo", "Preparing qe-sap-deployment repository");

    my $git_repo = get_var(QESAPDEPLOY_GITHUB_REPO => 'github.com/SUSE/qe-sap-deployment');
    enter_cmd "cd " . DEPLOYMENT_DIR;

    # Script from a release
    if (get_var('QESAPDEPLOY_VER')) {
      my $ver_artifact = 'v' . get_var('QESAPDEPLOY_VER') . '.tar.gz';

      my $curl_cmd = "curl -v -L https://$git_repo/archive/refs/tags/$ver_artifact -o$ver_artifact";
      assert_script_run("set -o pipefail ; $curl_cmd | tee " . QESAP_GIT_CLONE_LOG, quiet => 1);

      my $tar_cmd = "tar xvf $ver_artifact --strip-components=1";
      assert_script_run($tar_cmd);
      enter_cmd 'ls -lai';
    }
    else {
      # Get the code for the qe-sap-deployment by cloning its repository
      assert_script_run('git config --global http.sslVerify false', quiet => 1) if get_var('QESAPDEPLOY_GIT_NO_VERIFY');
      my $git_branch = get_var('QESAPDEPLOY_GITHUB_BRANCH', 'main');


      my $git_clone_cmd = 'git clone --depth 1 --branch ' . $git_branch . ' https://' . $git_repo . ' ' . DEPLOYMENT_DIR;
      push(@log_files, QESAP_GIT_CLONE_LOG);
      assert_script_run("set -o pipefail ; $git_clone_cmd | tee " . QESAP_GIT_CLONE_LOG, quiet => 1);
      #assert_script_run("git pull");
      #assert_script_run("git checkout " . $git_branch);
    }
}

=head3 get_resource_group

Return a string to be used as cloud resource group.
It contains the JobId
=cut

sub get_resource_group {
    my $job_id = get_current_job_id();
    return QESAPDEPLOY_PREFIX . "rg$job_id";
}

=head3 qesap_configure_tfvar

Generate a terraform.tfvars from a template.

=over 3

=item B<PROVIDER> - cloud provider, used to select
                    the right folder in the qe-sap-deploy repo

=item B<REGION> - cloud region where to perform the deployment.
                  Used for %REGION%

=item B<OS_VERSION> - string for the OS version to be used for the deployed machine.
                      Used for %OSVER%

=back
=cut

sub qesap_configure_tfvar {
    my ($self, $provider, $region, $os_version) = @_;
    my $tfvar = DEPLOYMENT_DIR . '/terraform/' . lc($provider) . '/terraform.tfvars';
    assert_script_run("cp $tfvar.openqa $tfvar");
    push(@log_files, $tfvar);
    file_content_replace($tfvar,
        q(%REGION%) => $region,
        q(%DEPLOYMENTNAME%) => get_resource_group(),
        q(%OSVER%) => $os_version,
        q(%SSHKEY%) => SSH_KEY
    );
    upload_logs($tfvar);
}

=head3 qesap_configure_variables

Generate the variables.sh loaded by build.sh and destroy.sh

=over 1

=item B<PROVIDER> - cloud provider, used to select
                    the right folder in the qe-sap-deploy repo

=item B<SAP_REGCODE> - SCC code

=back
=cut

sub qesap_configure_variables {
    my ($self, $provider, $sap_regcode) = @_;

    my $variables_sh = DEPLOYMENT_DIR . '/variables.sh';

    # is it a good idea to save variables.sh? as it has the SCC code.
    push(@log_files, $variables_sh);

    # variables.sh file
    enter_cmd 'echo "PROVIDER=' . lc($provider) . '" > ' . $variables_sh;
    enter_cmd "echo \"REG_CODE='$sap_regcode'\" >> $variables_sh";
    enter_cmd "echo \"EMAIL='testing\@suse.com'\" >> $variables_sh";
    enter_cmd "echo \"SAPCONF='true'\" >> $variables_sh";
    enter_cmd "echo \"export REG_CODE EMAIL SAPCONF\" >> $variables_sh";
    upload_logs($variables_sh);
}

=head3 qesap_configure_hanamedia

Generate the hana_media.yaml for Ansible

=over 3

=item B<SAPCAR> - blob server url for the SAPCAR

=item B<IMDB_SERVER> - blob server url for the IMDB_SERVER

=item B<IMDB_CLIENT> - blob server url for the IMDB_CLIENT

=back
=cut

sub qesap_configure_hanamedia {
    my ($self, $sapcar, $imbd_server, $imbd_cient) = @_;
    my $media_var = DEPLOYMENT_DIR . '/ansible/playbooks/vars/azure_hana_media.yaml';
    assert_script_run("cp $media_var.openqa $media_var");

    push(@log_files, $media_var);
    file_content_replace($media_var,
        q(%SAPCAR%) => $sapcar,
        q(%IMDB_SERVER%) => $imbd_server,
        q(%IMDB_CLIENT%) => $imbd_cient);
    upload_logs($media_var);
}

=head3 qesap_deploy

Call build.sh and publish all the logs

=cut

sub qesap_deploy {
    my $log = DEPLOYMENT_DIR . '/build.log.txt';
    enter_cmd 'cd ' . DEPLOYMENT_DIR;
    my $cmd = 'set -o pipefail ;' .
      ' ./build.sh -q -k ' . SSH_KEY .
      "| tee $log";
    push(@log_files, $log);
    assert_script_run($cmd, (45 * 60));

    upload_logs($log);
}

=head3 qesap_destroy

Call destroy.sh and publish all the logs

=cut

sub qesap_destroy {
    enter_cmd 'cd ' . DEPLOYMENT_DIR;
    my $log = DEPLOYMENT_DIR . '/destroy.log.txt';
    my $cmd = 'set -o pipefail ;' .
      ' ./destroy.sh -q -k ' . SSH_KEY .
      "| tee $log";
    push(@log_files, $log);
    assert_script_run($cmd, (15 * 60));

    upload_logs($log);
}

1;
