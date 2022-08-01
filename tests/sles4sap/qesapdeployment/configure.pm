# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# Summary: Configuration steps for qe-sap-deployment
# Maintainer: QE-SAP <qe-sap@suse.de>, Michele Pagot <michele.pagot@suse.com>

use strict;
use warnings;
use Mojo::Base 'publiccloud::basetest';
use testapi;
use utils qw(file_content_replace);
use base 'qesapdeployment';

use constant GIT_CLONE_LOG => '/tmp/git_clone.log';

sub run {
    my ($self) = @_;
    $self->select_serial_terminal;

    # Get the code for the qe-sap-deployment
    my $git_branch = get_var('QESAPDEPLOY_GITHUB_BRANCH', 'main');

    enter_cmd 'cd ~/test/qe-sap-deployment';
    assert_script_run("git pull");
    assert_script_run("git checkout " . $git_branch);

    # Init al the PC gears (ssh keys)
    my $provider = $self->provider_factory();

    # tfvars file
    $self->configure_tfvar('/root/test/qe-sap-deployment',
        get_required_var('PUBLIC_CLOUD_PROVIDER'),
        $provider->provider_client->region,
        get_required_var('QESAPDEPLOY_OS_VER'));

    # variables.sh file
    $self->configure_variables('/root/test/qe-sap-deployment',
        get_required_var('PUBLIC_CLOUD_PROVIDER'),
        get_required_var('SCC_REGCODE_SLES4SAP'));

    # Ansible blob file
    $self->configure_hanamedia('/root/test/qe-sap-deployment',
        get_var('QESAPDEPLOY_SAPCAR'),
        get_var('QESAPDEPLOY_IMDB_SERVER'),
        get_var('QESAPDEPLOY_IMDB_CLIENT'));
}

sub post_fail_hook {
    my ($self) = shift;
    $self->select_serial_terminal;
    enter_cmd 'cd  ~/test/qe-sap-deployment';
    upload_logs('terraform/' . lc(get_required_var('PUBLIC_CLOUD_PROVIDER')) . '/terraform.tfvars');
    # is it a good idea to save variables.sh? as it has the SCC code.
    upload_logs('variables.sh');
    $self->SUPER::post_fail_hook;
}

1;
