# SUSE's openQA tests
#
# Copyright 2021-2025 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# Summary: Test aws-efs-utils package
# Maintainer: QE-C team <qa-c@suse.de>

use Mojo::Base 'publiccloud::basetest';
use testapi;
use serial_terminal 'select_serial_terminal';
use mmapi 'get_current_job_id';
use utils qw(zypper_call script_retry);
#use version_utils 'is_sle';
#use publiccloud::utils 'detect_worker_ip';
#use registration qw(add_suseconnect_product get_addon_fullname);
#use publiccloud::utils qw(calculate_custodian_ttl);

#my $silent = (is_sle('>=16')) ? '%silent' : '';
my $silent = '';

sub run {
    my ($self, $args) = @_;
    select_serial_terminal;
    my $job_id = get_current_job_id();

    script_run("which aws");
    zypper_call 'se -s aws-efs-utils';
    zypper_call 'in aws-efs-utils';
    my $files = script_output('rpm -ql aws-efs-utils', quiet => 1);
    my @file_list = grep { length } split(/\r?\n/, $files);
    my $file_table = '';
    for my $file (@file_list) {
        $file =~ s/^\s+|\s+$//g;
        next unless $file;
        my $type = script_output("file $file", quiet => 1);
        $file_table .= "$type\n";
    }
    record_info('aws-efs-utils', $file_table);

    my ($efs_proxy) = grep { /efs-proxy/ } @file_list;
    if ($efs_proxy) {
        script_run("$efs_proxy --help");
    }
    script_run('man mount.efs');

    my $provider = $self->provider_factory();

    # --- Create EFS File System ---
    my $creation_token = "openqa-efs-test-$job_id";
    my $openqa_url = get_var('OPENQA_URL', get_var('OPENQA_HOSTNAME'));
    my $created_by = "$openqa_url/t$job_id";
    my $openqa_ttl = get_var('MAX_JOB_TIME', 7200) + get_var('PUBLIC_CLOUD_TTL_OFFSET', 300);

    my $create_efs = "aws efs create-file-system --creation-token '$creation_token'";
    $create_efs .= " --encrypted --performance-mode generalPurpose --throughput-mode elastic";
    $create_efs .= " --tags Key=Name,Value=openqa-efs-test-$job_id Key=openqa_created_by,Value=$created_by Key=openqa_ttl,Value=$openqa_ttl";
    assert_script_run($create_efs, 180);

    my $fs_id = script_output("aws $silent efs describe-file-systems --creation-token '$creation_token' --query 'FileSystems[0].FileSystemId' --output text", 90);
    record_info('EFS FS', $fs_id);

    # Wait for file system to become available
    my $max_retries = 24;
    for my $i (1 .. $max_retries) {
        my $state = script_output("aws $silent efs describe-file-systems --file-system-id $fs_id --query 'FileSystems[0].LifeCycleState' --output text", 90);
        last if ($state eq 'available');
        die "EFS $fs_id still in state '$state' after $max_retries attempts" if ($i == $max_retries);
        record_info('EFS wait', "Attempt $i/$max_retries: state=$state");
        sleep 5;
    }

}

sub cleanup {
    my ($assert) = @_;
    $assert //= 0;

    my $job_id = get_current_job_id();
    my $creation_token = "openqa-efs-test-$job_id";

    # Delete EFS file system
    my $fs_id = script_output("aws $silent efs describe-file-systems --creation-token '$creation_token' --query 'FileSystems[0].FileSystemId' --output text", timeout => 90, proceed_on_failure => 1);
    if ($fs_id && $fs_id ne 'None') {
        record_info('Cleanup', "Deleting EFS $fs_id");
        if ($assert) {
            assert_script_run("aws efs delete-file-system --file-system-id $fs_id");
        } else {
            script_run("aws efs delete-file-system --file-system-id $fs_id");
        }
    }

    return 1;
}

sub post_run_hook {
    cleanup(1);
}

sub post_fail_hook {
    cleanup();
}

sub test_flags {
    return {fatal => 0, milestone => 0};
}

1;
