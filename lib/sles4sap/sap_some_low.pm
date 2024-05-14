# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary: Library sub and shared data for the ipaddr2 cloud test.

package sles4sap::sap_some_low;
use strict;
use warnings FATAL => 'all';
use testapi;
use Carp qw(croak);
use Exporter qw(import);


=head1 SYNOPSIS

Library to manage something
=cut

our @EXPORT = qw(
  low_greeting
  low_init
  low_read
  low_read_complex
  low_loop
);



=head2 low_greeting

    low_greeting(
        name => 'yourname')

Greeting you
=over 1

=item B<name> - your name

=back
=cut

sub low_greeting {
    my (%args) = @_;
    croak("Argument < name > missing") unless $args{name};

    return uc(reverse($args{name}));
}


=head2 low_init

    low_init(
        group => 'openqa-rg',
        region => 'westeurope',
        vnet => 'openqa-vnet',
        snet => 'openqa-subnet',
        address_prefixes => '10.0.1.0/16',
        subnet_prefixes => '10.0.1.0/24')

Init something low
=over 6

=item B<group> - existing group where to create the thing

=item B<region> - the region

=item B<vnet> - name of the virtual network

=item B<snet> - name of the subnet

=item B<address_prefixes> - virtual network ip address space. Default 192.168.0.0/16

=item B<subnet_prefixes> - subnet ip address space. Default 192.168.0.0/24

=back
=cut

sub low_init {
    my (%args) = @_;
    foreach (qw(group region vnet snet)) {
        croak("Argument < $_ > missing") unless $args{$_}; }
    $args{address_prefixes} //= '192.168.0.0/16';
    $args{subnet_prefixes} //= '192.168.0.0/24';

    my $cmd = join(' ', 'lowlowlow initialize',
        '--group', $args{group},
        '--location', $args{region},
        '--name', $args{vnet},
        '--address-prefixes', $args{address_prefixes},
        '--subnet-name', $args{snet},
        '--subnet-prefixes', $args{subnet_prefixes});
    assert_script_run($cmd);
}

=head2 low_read

    low_read(
        group => 'openqa-rg',
        region => 'westeurope')

Read and return something low
=over 6

=item B<group> - existing group where to create the thing

=item B<region> - the region

=back
=cut

sub low_read {
    my (%args) = @_;
    foreach (qw(group region)) {
        croak("Argument < $_ > missing") unless $args{$_}; }

    my $cmd = join(' ', 'lowlowlow read',
        '--group', $args{resource_group},
        '--location', $args{region});
    return script_output($cmd);
}

=head2 low_read_complex

    low_read(
        group => 'openqa-rg',
        region => 'westeurope')

Read and return something low
=over 6

=item B<group> - existing group where to create the thing

=item B<region> - the region

=back
=cut

sub low_read_complex {
    my (%args) = @_;
    foreach (qw(group region)) {
        croak("Argument < $_ > missing") unless $args{$_}; }

    my $cmd = join(' ', 'lowlowlow read-id',
        '--group', $args{resource_group},
        '--location', $args{region});
    my $out = script_output($cmd);

    if ($out =~ m/((a\d+)?)*/) {
        assert_script_run("lowlowlow something --id $1");
    }
}


=head2 low_loop

    low_read(
        group => 'openqa-rg',
        region => 'westeurope')

Read and return something low until ...
=over 6

=item B<group> - existing group where to create the thing

=item B<region> - the region

=back
=cut

sub low_loop {
    my (%args) = @_;
    foreach (qw(group region)) {
        croak("Argument < $_ > missing") unless $args{$_}; }

    $args{timeout} //= 3600;

    my $cmd = join(' ', 'lowlowlow status',
        '--group', $args{resource_group},
        '--location', $args{region});
    my $start_time = time;
    while (script_output($cmd) =~ m/STARTED/) {
        if (time - $start_time > $args{timeout}) {
            #record_info("Cluster status", $self->run_cmd(cmd => $crm_mon_cmd));
            #die("Resource did not start within defined timeout. ($timeout sec).");
        }
        sleep 30;
    }
}
