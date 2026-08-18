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

my $silent = '';

sub run {
    my ($self, $args) = @_;
    select_serial_terminal;
    my $job_id = get_current_job_id();

    script_run("which aws");

    my $instance = $args->{my_instance};

    # Install and inspect aws-efs-utils on the remote EC2 SUT
    $instance->ssh_assert_script_run('sudo zypper -n se -s aws-efs-utils', timeout => 120);
    $instance->ssh_assert_script_run('sudo zypper -n in aws-efs-utils', timeout => 300);

    my $files = $instance->ssh_script_output('rpm -ql aws-efs-utils', quiet => 1);
    my @file_list = grep { /\S/ } split(/\r?\n/, $files);
    my $files_args = join(' ', @file_list);
    my $file_table = $instance->ssh_script_output("file $files_args", quiet => 1);
    record_info('aws-efs-utils', $file_table);

    my ($efs_proxy) = grep { /\/efs-proxy$/ } @file_list;
    if ($efs_proxy) {
        $instance->ssh_assert_script_run("$efs_proxy --help");
    }

    # Man page: assert the gz is present, try to install man, try to read it
    $instance->ssh_assert_script_run('test -f /usr/share/man/man8/mount.efs.8.gz');
    $instance->ssh_script_run('sudo zypper -n in man', timeout => 120);
    $instance->ssh_script_run('man mount.efs', timeout => 30);

    # --- Create EFS File System (AWS CLI on worker) ---
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

    my $max_retries = 24;
    for my $i (1 .. $max_retries) {
        my $state = script_output("aws $silent efs describe-file-systems --file-system-id $fs_id --query 'FileSystems[0].LifeCycleState' --output text", 90);
        last if ($state eq 'available');
        die "EFS $fs_id still in state '$state' after $max_retries attempts" if ($i == $max_retries);
        record_info('EFS wait', "Attempt $i/$max_retries: state=$state");
        sleep 5;
    }

    # --- Discover SUT network topology (AWS CLI on worker) ---
    my $instance_id = $instance->instance_id;
    my $subnet_id = script_output("aws ec2 describe-instances --instance-ids $instance_id " .
        "--query 'Reservations[0].Instances[0].SubnetId' --output text", 60);
    my $vpc_id = script_output("aws ec2 describe-subnets --subnet-ids $subnet_id " .
        "--query 'Subnets[0].VpcId' --output text", 30);
    my $vpc_cidr = script_output("aws ec2 describe-vpcs --vpc-ids $vpc_id " .
        "--query 'Vpcs[0].CidrBlock' --output text", 30);

    # Triage: VPC DNS attributes — both must be true for EFS DNS-based mount to work
    my $dns_hostnames = script_output("aws ec2 describe-vpc-attribute --vpc-id $vpc_id " .
        "--attribute enableDnsHostnames --query 'EnableDnsHostnames.Value' --output text", 30);
    my $dns_support = script_output("aws ec2 describe-vpc-attribute --vpc-id $vpc_id " .
        "--attribute enableDnsSupport --query 'EnableDnsSupport.Value' --output text", 30);
    record_info('VPC DNS attrs', "enableDnsHostnames=$dns_hostnames\nenableDnsSupport=$dns_support");

    # --- Create security group and mount target ---
    my $sg_id = script_output("aws ec2 create-security-group " .
        "--group-name 'openqa-efs-sg-$job_id' " .
        "--description 'openqa EFS test SG' " .
        "--vpc-id $vpc_id " .
        "--query 'GroupId' --output text", 60);
    assert_script_run("aws ec2 authorize-security-group-ingress " .
        "--group-id $sg_id --protocol tcp --port 2049 --cidr $vpc_cidr");

    my $mt_id = script_output("aws efs create-mount-target " .
        "--file-system-id $fs_id " .
        "--subnet-id $subnet_id " .
        "--security-groups $sg_id " .
        "--query 'MountTargetId' --output text", 60);
    record_info('EFS MT', $mt_id);

    script_retry("aws efs describe-mount-targets --mount-target-id $mt_id " .
        "--query 'MountTargets[0].LifeCycleState' --output text | grep -w available",
        retry => 24, delay => 10, timeout => 15);

    # Get mount target IP and AZ for triage and fallback
    my $mt_ip = script_output("aws efs describe-mount-targets --mount-target-id $mt_id " .
        "--query 'MountTargets[0].IpAddress' --output text", 30);
    my $mt_az = script_output("aws efs describe-mount-targets --mount-target-id $mt_id " .
        "--query 'MountTargets[0].AvailabilityZoneName' --output text", 30);
    record_info('EFS MT details', "id=$mt_id\nip=$mt_ip\naz=$mt_az");

    # Triage: SUT AZ vs mount target AZ (mismatch breaks DNS-based mount)
    my $sut_az = script_output("aws ec2 describe-instances --instance-ids $instance_id " .
        "--query 'Reservations[0].Instances[0].Placement.AvailabilityZone' --output text", 30);
    record_info('AZ check', "SUT az=$sut_az  mount target az=$mt_az");

    # Build EFS DNS name
    my $region = $instance->region;
    my $efs_dns = "$fs_id.efs.$region.amazonaws.com";
    record_info('EFS DNS name', $efs_dns);

    # Triage: DNS resolution from the SUT (inside the VPC — expected to work)
    my $dns_sut = $instance->ssh_script_output(
        "getent hosts $efs_dns 2>&1 || nslookup $efs_dns 2>&1 || echo DNS_FAILED",
        proceed_on_failure => 1, quiet => 1);
    record_info('DNS from SUT', $dns_sut);

    # Triage: DNS resolution from the worker (outside the VPC — expected to fail, documents gap)
    my $dns_worker = script_output(
        "getent hosts $efs_dns 2>&1 || nslookup $efs_dns 2>&1 || echo DNS_FAILED_WORKER",
        proceed_on_failure => 1);
    record_info('DNS from worker', $dns_worker);

    # Triage: NFS port reachability from SUT to mount target IP
    my $nfs_port = $instance->ssh_script_output(
        "nc -zv -w5 $mt_ip 2049 2>&1 || echo NFS_PORT_UNREACHABLE",
        proceed_on_failure => 1, quiet => 1);
    record_info('NFS port SUT', $nfs_port);

    # --- Mount EFS on SUT: try DNS first, fall back to mounttargetip ---
    $instance->ssh_assert_script_run('sudo mkdir -p /mnt/efs');
    my $mount_ret = $instance->ssh_script_run(
        "sudo mount -t efs -o tls $fs_id:/ /mnt/efs", timeout => 60);
    if ($mount_ret != 0) {
        record_info('Mount DNS fallback',
            "DNS-based mount failed (exit $mount_ret); retrying with mounttargetip=$mt_ip");
        $instance->ssh_assert_script_run(
            "sudo mount -t efs -o tls,mounttargetip=$mt_ip $fs_id:/ /mnt/efs", timeout => 60);
    }
    record_info('EFS mount', 'EFS mounted successfully');

    $instance->ssh_assert_script_run("echo 'openqa-efs-test' | sudo tee /mnt/efs/test.txt");
    $instance->ssh_assert_script_run("sudo cat /mnt/efs/test.txt | grep -q 'openqa-efs-test'");
    $instance->ssh_assert_script_run("sudo df -h /mnt/efs");
    $instance->ssh_assert_script_run("sudo ls -la /mnt/efs/");
    $instance->ssh_assert_script_run("sudo umount /mnt/efs");
}

sub cleanup {
    my ($assert) = @_;
    $assert //= 0;

    my $job_id = get_current_job_id();
    my $creation_token = "openqa-efs-test-$job_id";

    my $fs_id = script_output(
        "aws $silent efs describe-file-systems --creation-token '$creation_token' " .
        "--query 'FileSystems[0].FileSystemId' --output text",
        timeout => 90, proceed_on_failure => 1);

    if ($fs_id && $fs_id ne 'None') {
        my $mt_id = script_output(
            "aws $silent efs describe-mount-targets --file-system-id $fs_id " .
            "--query 'MountTargets[0].MountTargetId' --output text",
            timeout => 30, proceed_on_failure => 1);

        if ($mt_id && $mt_id ne 'None') {
            record_info('Cleanup', "Deleting mount target $mt_id");
            script_run("aws efs delete-mount-target --mount-target-id $mt_id");
            script_retry(
                "aws efs describe-mount-targets --mount-target-id $mt_id " .
                "--query 'MountTargets[0].LifeCycleState' --output text 2>&1 | grep -v deleting",
                retry => 24, delay => 10, die => 0, timeout => 15);
        }

        record_info('Cleanup', "Deleting EFS $fs_id");
        if ($assert) {
            assert_script_run("aws efs delete-file-system --file-system-id $fs_id");
        } else {
            script_run("aws efs delete-file-system --file-system-id $fs_id");
        }
    }

    my $sg_id = script_output(
        "aws ec2 describe-security-groups " .
        "--filters 'Name=group-name,Values=openqa-efs-sg-$job_id' " .
        "--query 'SecurityGroups[0].GroupId' --output text",
        timeout => 30, proceed_on_failure => 1);
    if ($sg_id && $sg_id ne 'None') {
        record_info('Cleanup', "Deleting SG $sg_id");
        script_run("aws ec2 delete-security-group --group-id $sg_id");
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
