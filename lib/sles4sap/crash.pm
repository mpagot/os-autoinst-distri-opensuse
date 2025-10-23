# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary: Library sub and shared data for the crash cloud test.

package sles4sap::crash;

use strict;
use warnings FATAL => 'all';
use Mojo::Base -signatures;
use testapi;
use mmapi qw( get_current_job_id );
use Carp qw( croak );
use Exporter qw(import);
use sles4sap::azure_cli;
use sles4sap::aws_cli;
use version_utils qw(is_sle);

=head1 SYNOPSIS

Library to manage cloud crash tests
=cut

our @EXPORT = qw(
  crash_deploy_name
  crash_deploy_azure
  crash_pubip
  crash_system_ready
  crash_softrestart
  crash_destroy_azure
  crash_destroy_aws
);

use constant DEPLOY_PREFIX => 'crash';
use constant USER => 'cloudadmin';
use constant SSH_KEY_ID => 'id_rsa';

=head2 crash_deploy_name

    my $name = crash_deploy_name();

Return the deploy name. Azure use it as resource group name
=cut

sub crash_deploy_name {
    return DEPLOY_PREFIX . get_current_job_id();
}


=head2 crash_deploy_azure

Run the Azure deployment
=over

=item B<region> - existing resource group

=item B<os> - existing Load balancer NAME

=back
=cut

sub crash_deploy_azure(%args) {
    foreach (qw(region os)) {
        croak("Argument < $_ > missing") unless $args{$_}; }

    my $rg = crash_deploy_name();
    az_group_create(name => $rg, region => $args{region});

    my $os_ver;
    if ($args{os} =~ /\.vhd$/) {
        my $img_name = $rg . 'img';
        az_img_from_vhd_create(
            resource_group => $rg,
            name => $img_name,
            source => $args{os});
        $os_ver = $img_name;
    }
    else {
        $os_ver = $args{os};
    }

    my $nsg = DEPLOY_PREFIX . '-nsg';
    az_network_nsg_create(resource_group => $rg, name => $nsg);
    az_network_nsg_rule_create(resource_group => $rg, nsg => $nsg, name => $nsg . 'RuleSSH', port => 22);

    my $pub_ip_name = DEPLOY_PREFIX . '-pub_ip';
    az_network_publicip_create(resource_group => $rg, name => $pub_ip_name, zone => '1 2 3');

    my $vnet = DEPLOY_PREFIX . '-vnet';
    my $subnet = DEPLOY_PREFIX . '-snet';
    az_network_vnet_create(
        resource_group => $rg,
        region => $args{region},
        vnet => $vnet,
        address_prefixes => '10.1.0.0/16',
        snet => $subnet,
        subnet_prefixes => '10.1.0.0/24');

    my $nic = DEPLOY_PREFIX . '-nic';
    az_nic_create(
        resource_group => $rg,
        name => $nic,
        vnet => $vnet,
        subnet => $subnet,
        nsg => $nsg,
        pubip_name => $pub_ip_name);

    my %vm_create_args = (
        resource_group => $rg,
        name => DEPLOY_PREFIX . '-vm',
        image => $os_ver,
        nic => $nic,
        username => USER,
        region => $args{region});
    $vm_create_args{security_type} = 'Standard' if is_sle('<=12-SP5');
    az_vm_create(%vm_create_args);

    az_vm_wait_running(
        resource_group => crash_deploy_name(),
        name => DEPLOY_PREFIX . '-vm',
        timeout => 1200);
}


=head2 crush_pubip

Get the deployment public IP of the VM. Die if an
unsupported csp name is provided.
=over

=item B<PROVIDER> - Cloud provider name using same format of PUBLIC_CLOUD_PROVIDER setting

=back
=cut
sub crash_pubip(%args) {
    croak "Missing mandatory argument 'provider'" unless $args{provider};
    my $vm_ip = '';
    if ($args{provider} eq 'EC2') {
        $vm_ip = aws_get_ip_address(
            aws_vm_get_id($args{provider}),
            crash_deploy_name());
    }
    elsif ($args{provider} eq 'AZURE') {
        $vm_ip = az_network_publicip_get(
            resource_group => crash_deploy_name(),
            name => DEPLOY_PREFIX . "-pub_ip");
    }
    else {
        die "Not supported provider '$args{provider}'";
    }
    return $vm_ip;
}


=head2 crash_system_ready

    Polls C<systemctl is-system-running> via SSH for up to 5 minutes.
    If C<reg_code> is provided, registers the system using C<registercloudguest> and verifies with C<SUSEConnect -s>.

=over

=item B<reg_code> Registration code.

=item B<ssh_command> SSH command for registration.

=back
=cut

sub crash_system_ready(%args) {
    croak "Missing mandatory argument 'ssh_command'" unless $args{ssh_command};
    my $ret;

    my $start_time = time();
    while ((time() - $start_time) < 300) {
        $ret = script_run(join(' ', $args{ssh_command}, 'sudo', 'systemctl is-system-running'));
        last unless $ret;
        sleep 10;
    }
    return unless ($args{reg_code});

    script_run(join(' ', $args{ssh_command}, 'sudo SUSEConnect -s'), 200);
    script_run(join(' ', $args{ssh_command}, 'sudo registercloudguest --clean'), 200);

    my $rc = 1;
    my $attempt = 0;

    while ($rc != 0 && $attempt < 4) {
        $rc = script_run("$args{ssh_command} sudo registercloudguest --force-new -r $args{reg_code} -e testing\@suse.com", 600);
        record_info('REGISTER CODE', $rc);
        $attempt++;
    }
    die "registercloudguest failed after $attempt attempts with exit $rc" unless ($rc == 0);
    assert_script_run(join(' ', $args{ssh_command}, 'sudo SUSEConnect -s'));
}


=head2 crash_softrestart

    crash_softrestart(instance => $instance [, timeout => 600]);

Does a soft restart of the given C<instance> by running the command C<shutdown -r>.

=over

=item B<instance> instance of the PC class.

=item B<timeout>

=back
=cut
sub crash_softrestart(%args) {
    croak "Missing mandatory argument 'instance'" unless $args{instance};
    $args{timeout} //= 600;

    $args{instance}->ssh_assert_script_run(
        cmd => 'sudo /sbin/shutdown -r +1',
        ssh_opts => '-o StrictHostKeyChecking=no');
    sleep 60;

    my $start_time = time();
    # wait till ssh disappear
    my $out = $args{instance}->wait_for_ssh(
        timeout => $args{timeout},
        wait_stop => 1,
        'cloudadmin');
    # ok ssh port closed
    record_info("Shutdown failed",
        "WARNING: while stopping the system, ssh port still open after timeout,\nreporting: $out")
      if (defined $out);    # not ok port still open

    my $shutdown_time = time() - $start_time;
    $args{instance}->wait_for_ssh(
        timeout => $args{timeout} - $shutdown_time,
        'cloudadmin',
        0);
}


=head2 crash_destroy_azure

Delete the Azure deployment

=cut

sub crash_destroy_azure {
    my $rg = crash_deploy_name();
    record_info('AZURE CLEANUP', "Deleting resource group: $rg");
    az_group_delete(name => $rg);
}


=head2 crash_destroy_aws

Delete the AWS deployment

=over

=item B<region> region where the deployment has been deployed in AWS

=back
=cut

sub crash_destroy_aws(%args) {
    croak "Missing mandatory argument 'region'" unless $args{region};
    my $job_id = $crash_deploy_name ();

    my $instance_id = aws_vm_get_id($args{region}, $job_id);
    my $vpc_id = aws_vpc_get_id($args{region}, $job_id);

    # Terminate instance and wait
    script_run("aws ec2 terminate-instances --instance-ids $instance_id --region $region");
    script_run("aws ec2 wait instance-terminated --instance-ids $instance_id --region $region", timeout => 300);
    # Delete all resources
    assert_script_run("aws ec2 delete-security-group --group-id " . aws_get_security_group_id($region, $job_id) . " --region $region");
    assert_script_run("aws ec2 delete-subnet --subnet-id " . aws_subnet_get_id($region, $job_id) . " --region $region");
    my $igw_id = aws_get_internet_gateway_id($region, $job_id);
    script_run("aws ec2 detach-internet-gateway --vpc-id $vpc_id --internet-gateway-id $igw_id --region $region");
    script_run("aws ec2 delete-internet-gateway --internet-gateway-id $igw_id --region $region");
    my $rtb_ids = script_output(
        "aws ec2 describe-route-tables --filters Name=vpc-id,Values=$vpc_id" .
          " --query 'RouteTables[?Associations[0].Main!=\`true\`].RouteTableId'" .
          " --output text --region $region");
    assert_script_run("aws ec2 delete-route-table --route-table-id $_ --region $region") for split(/\s+/, $rtb_ids);

    # Delete everything else (AWS handles dependencies automatically if we wait)
    script_run("aws ec2 delete-vpc --vpc-id $vpc_id --region $region");
}

1;
