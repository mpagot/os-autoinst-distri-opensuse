# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# Summary: Test for qe-sap-deployment
# Maintainer: QE-SAP <qe-sap@suse.de>, Michele Pagot <michele.pagot@suse.com>

use strict;
use warnings;
use Mojo::Base 'publiccloud::basetest';
use base 'consoletest';
use testapi;

use constant GIT_CLONE_LOG => '/tmp/git_clone.log';

use constant QESAPDEPLOY_PREFIX => 'qesapdep';

=head3 get_resource_group

Return a string to be used as cloud resource group.
It contains the JobId
=cut
sub get_resource_group {
    my $job_id = get_current_job_id();
    return QESAPDEPLOY_PREFIX . "rg$job_id";
}


sub run {
    my ($self) = @_;
    $self->select_serial_terminal;

    enter_cmd 'cd ~/test/qe-sap-deployment';
    assert_script_run('set -o pipefail ; ./destroy.sh -q -k ~/.ssh/id_rsa | tee destroy.log.txt', (15 * 60));

}

sub post_fail_hook {
    my ($self) = shift;
    $self->select_serial_terminal;
    enter_cmd 'cd ~/test/qe-sap-deployment';
    upload_logs('terraform.init.log.txt', failok => 1);
    upload_logs('terraform.plan.log.txt', failok => 1);
    upload_logs('terraform.apply.log.txt', failok => 1);
    upload_logs('terraform.destroy.log.txt', failok => 1);
    upload_logs('destroy.log.txt', failok => 1);
    upload_logs('ansible.build.log.txt', failok => 1);
    upload_logs('ansible.destroy.log.txt', failok => 1);

    assert_script_run('./destroy.sh -k ~/.ssh/id_rsa', (15 * 60));
    $self->SUPER::post_fail_hook;
}

1;
