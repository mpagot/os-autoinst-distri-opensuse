# SUSE's openQA tests
#
# Copyright 2022 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Summary: Functions to use qe-sap-deployment project
# Maintainer: QE-SAP <qe-sap@suse.de>

## no critic (RequireFilenameMatchesPackage);

=encoding utf8

=head1 NAME

    qe-sap-deployment test lib

=head1 COPYRIGHT

    Copyright 2022 SUSE LLC
    SPDX-License-Identifier: FSFAP

=head1 AUTHORS

    QE SAP <qe-sap@suse.de>

=cut

package qesapdeployment;

use strict;
use warnings;
use utils 'file_content_replace';
use testapi;
#use mmapi 'get_current_job_id';
use Exporter 'import';
my @log_files = ();

# Constants
use constant PROVIDER => lc get_required_var('PUBLIC_CLOUD_PROVIDER');
use constant QESAP_GIT_CLONE_LOG => '/tmp/git_clone.txt';
use constant DEPLOYMENT_DIR => get_var('DEPLOYMENT_DIR', '/root/qe-sap-deployment');
use constant PIP_INSTALL_LOG => '/tmp/pip_install.txt';
use constant TERRAFORM_DIR => get_var('PUBLIC_CLOUD_TERRAFORM_DIR', DEPLOYMENT_DIR . '/terraform/');
use constant QESAP_CONF_FILENAME => get_required_var('QESAP_CONFIG_FILE');
use constant QESAP_CONF_SRC => "sles4sap/qe_sap_deployment/" . QESAP_CONF_FILENAME;
use constant QESAP_CONF_TRGT => DEPLOYMENT_DIR . "/scripts/qesap/" . QESAP_CONF_FILENAME;

# Terraform requirement
#  terraform/azure/infrastructure.tf  "azurerm_storage_account" "mytfstorageacc"
# stdiag<PREFID><JOB_ID> can only consist of lowercase letters and numbers,
# and must be between 3 and 24 characters long
use constant QESAPDEPLOY_PREFIX => 'qesapdep';

our @EXPORT = qw(
  qesap_create_folder_tree
  qesap_pip_install
  qesap_upload_logs
  qesap_get_deployment_code
  get_resource_group
  qesap_configure_tfvar
  qesap_configure_variables
  qesap_configure_hanamedia
  qesap_configure_conf
  qesap_deploy
  qesap_translate_provider_name
  qesap_prepare_env
  qesap_execute
  qesap_yaml_replace
);

# Exported constants
#use constant VM_USER => 'cloudadmin';

# Lib internal constants



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
    record_info("QESAP repo", "Installing pip requirements");
    assert_script_run(join(" ", $pip_ints_cmd, 'awscli==1.19.48 | tee', PIP_INSTALL_LOG), 240);
    assert_script_run(join(" ", $pip_ints_cmd, '-r', DEPLOYMENT_DIR . '/requirements.txt | tee -a', PIP_INSTALL_LOG), 240);
    #assert_script_run('pip check');
}

=head3 qesap_upload_logs

    Collect and upload logs present in @log_files.

=over 1

=item B<FAILOK> - used as failok for the upload_logs. continue even in case upload fails

=back
=cut

sub qesap_upload_logs {
    my (%args) = @_;
    my $failok = $args{failok};
    record_info("Uploading logfiles", join("\n", @log_files));
    for my $file (@log_files) {
        upload_logs($file, failok => $failok);
    }
    # Remove already uploaded files from arrays
    @log_files = ();
}

=head3 qesap_get_deployment_code

    Get the qe-sap-deployment code
=cut

sub qesap_get_deployment_code {
    record_info("QESAP repo", "Preparing qe-sap-deployment repository");

    my $git_repo = get_var(QESAPDEPLOY_GITHUB_REPO => 'github.com/SUSE/qe-sap-deployment');
    enter_cmd "cd " . DEPLOYMENT_DIR;
    push(@log_files, QESAP_GIT_CLONE_LOG);

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
        assert_script_run("set -o pipefail ; $git_clone_cmd | tee " . QESAP_GIT_CLONE_LOG, quiet => 1);
        #assert_script_run("git pull");
        #assert_script_run("git checkout " . $git_branch);
    }
    # Add symlinks for different provider directory naming between OpenQA and qesap-deployment
    assert_script_run("ln -s " . TERRAFORM_DIR . "aws " . TERRAFORM_DIR . "/ec2");
    assert_script_run("ln -s " . TERRAFORM_DIR . "gcp " . TERRAFORM_DIR . "/gce");
}

=head3 qesap_yaml_replace

    Replaces yaml config file variables with parameters defined by OpenQA testode, yaml template or yaml schedule.
    Openqa variables need to be added as a hash with key/value pair inside %run_args{openqa_variables}.
    Example:
        my %variables;
        $variables{HANA_SAR} = get_required_var("HANA_SAR");
        $variables{HANA_CLIENT_SAR} = get_required_var("HANA_CLIENT_SAR");
        qesap_yaml_replace(openqa_variables=>\%variables);
=cut

sub qesap_yaml_replace {
    my (%args) = @_;
    my $variables = $args{openqa_variables};
    my %replaced_variables = ();

    push(@log_files, QESAP_CONF_TRGT);

    for my $variable (keys %{$variables}) {
        $replaced_variables{"%" . $variable . "%"} = $variables->{$variable};
    }
    file_content_replace(QESAP_CONF_TRGT, %replaced_variables);
    qesap_upload_logs();
}

=head3 qesap_execute

    qesap_execute(cmd => $qesap_script_cmd [, verbose => 1] );

    Execute qesap glue script commands. Check project documentation for available options:
    https://github.com/SUSE/qe-sap-deployment
=cut

sub qesap_execute {
    my (%args) = @_;
    die 'QESAP command to execute undefined' unless $args{cmd};

    my $verbose = $args{verbose} ? "--verbose" : "";
    my $qesap_cmd = join(" ", DEPLOYMENT_DIR . "/scripts/qesap/qesap.py", $verbose, "-c", QESAP_CONF_TRGT, "-b", DEPLOYMENT_DIR);
    my $exec_log = "/tmp/qesap_exec_" . $args{cmd} . ".log.txt";
    push(@log_files, $exec_log);

    record_info('QESAP exec', 'Executing: \n' . $qesap_cmd . " " . $args{cmd});

    if ($args{timeout}) {
        assert_script_run(join(" ", $qesap_cmd, $args{cmd}, "2>&1 | tee -a", $exec_log), timeout => $args{timeout});
    }
    else {
        assert_script_run(join(" ", $qesap_cmd, $args{cmd}, "2>&1 | tee -a", $exec_log));
    }

    qesap_upload_logs();
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

=head3 qesap_configure_tfvar

Generate a terraform.tfvars from a template.

=over 4

=item B<PROVIDER> - cloud provider, used to select
                    the right folder in the qe-sap-deploy repo

=item B<REGION> - cloud region where to perform the deployment.
                  Used for %REGION%

=item B<RESOURCE_GROUP_POSTFIX> - used as deployment_name in tfvars

=item B<OS_VERSION> - string for the OS version to be used for the deployed machine.
                      Used for %OSVER%

=back
=cut

sub qesap_configure_tfvar {
    my ($provider, $region, $resource_group_postfix, $os_version, $ssh_key) = @_;
    record_info("QESAP TFVARS", "provider:$provider region:$region resource_group_postfix:$resource_group_postfix os_version:$os_version ssh_key:$ssh_key");
    my $tfvar = DEPLOYMENT_DIR . '/terraform/' . lc($provider) . '/terraform.tfvars';
    assert_script_run("cp $tfvar.openqa $tfvar");
    push(@log_files, $tfvar);
    file_content_replace($tfvar,
        q(%REGION%) => $region,
        q(%DEPLOYMENTNAME%) => $resource_group_postfix,
        q(%OSVER%) => $os_version,
        q(%SSHKEY%) => $ssh_key
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
    my ($provider, $sap_regcode) = @_;

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
    my ($sapcar, $imbd_server, $imbd_cient) = @_;
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
    my ($ssh_key) = @_;
    my $log = DEPLOYMENT_DIR . '/build.log.txt';
    enter_cmd 'cd ' . DEPLOYMENT_DIR;
    my $cmd = 'set -o pipefail ;' .
      " ./build.sh -q -k $ssh_key" .
      "| tee $log";
    push(@log_files, $log);
    assert_script_run($cmd, (45 * 60));

    upload_logs($log);
}

=head3 qesap_destroy

Call destroy.sh and publish all the logs

=cut

sub qesap_destroy {
    my ($ssh_key) = @_;
    enter_cmd 'cd ' . DEPLOYMENT_DIR;
    my $log = DEPLOYMENT_DIR . '/destroy.log.txt';
    my $cmd = 'set -o pipefail ;' .
      " ./destroy.sh -q -k $ssh_key" .
      "| tee $log";
    push(@log_files, $log);
    assert_script_run($cmd, (15 * 60));

    upload_logs($log);
}

=head3 qesap_prepare_env

    qesap_prepare_env(variables=>{dict with variables});

    Prepare terraform environment.
    - creates file structures
    - pulls git repository
    - external config files
    - installs pip requirements and OS packages
    - generates config files with qesap script

    For variables example see 'qesap_yaml_replace'
=cut

sub qesap_prepare_env {
    my (%args) = @_;
    my $variables = $args{openqa_variables};
    my $tfvars_template = get_var('QESAP_TFVARS_TEMPLATE');
    qesap_create_folder_tree();
    qesap_get_deployment_code();
    qesap_pip_install();

    # Copy tfvars template file if defined in parameters
    if (get_var('QESAP_TFVARS_TEMPLATE')) {
        record_info("QESAP tfvars template", "Preparing terraform template: \n" . $tfvars_template);
        assert_script_run('cd ' . TERRAFORM_DIR . PROVIDER, quiet => 1);
        assert_script_run('cp ' . $tfvars_template . ' terraform.tfvars.template');
    }

    record_info("QESAP yaml", "Preparing yaml config file");
    my $curl = "curl -v -L ";
    assert_script_run($curl . data_url(QESAP_CONF_SRC) . ' -o ' . QESAP_CONF_TRGT);
    qesap_yaml_replace(openqa_variables => $variables);

    record_info("QESAP conf", "Generating tfvars file");
    push(@log_files, TERRAFORM_DIR . PROVIDER . "/terraform.tfvars");
    qesap_execute(cmd => 'configure');
    qesap_upload_logs();
}

=head3 qesap_configure_conf

    qesap_configure_conf(variables=>{dict with variables});

    Prepare the config.yaml for the quesap.py script
    - external config files

    For variables example see 'qesap_yaml_replace'
=cut

sub qesap_configure_conf {
    my (%args) = @_;
    my $variables = $args{openqa_variables};
    my $tfvars_template = get_var('QESAP_TFVARS_TEMPLATE');

    # Copy tfvars template file if defined in parameters
    if (get_var('QESAP_TFVARS_TEMPLATE')) {
        record_info("QESAP tfvars template", "Preparing terraform template: \n" . $tfvars_template);
        assert_script_run('cd ' . TERRAFORM_DIR . PROVIDER, quiet => 1);
        assert_script_run('cp ' . $tfvars_template . ' terraform.tfvars.template');
    }

    record_info("QESAP yaml", "Preparing yaml config file");
    my $curl = "curl -v -L ";
    assert_script_run($curl . data_url(QESAP_CONF_SRC) . ' -o ' . QESAP_CONF_TRGT);
    qesap_yaml_replace(openqa_variables => $variables);
}

1;
