# SUSE's openQA tests
#
# Copyright SUSE LLC
# SPDX-License-Identifier: FSFAP
# Maintainer: QE-SAP <qe-sap@suse.de>
# Summary: Library sub and shared data for the ipaddr2 cloud test.

package sles4sap::sap_some_high;
use strict;
use warnings FATAL => 'all';
use testapi;
use Carp qw(croak);
use Exporter qw(import);
use sles4sap::sap_some_low;


=head1 SYNOPSIS

Library to manage something
=cut

our @EXPORT = qw(
  high_init
);


sub high_init {
    low_init(group => 'openqa-rg',
        region => 'westeurope',
        vnet => 'openqa-vnet',
        snet => 'openqa-subnet');
    assert_script_run("highhighhigh init");
}

sub high_do_stuff {
    low_read(group => 'openqa-rg', region => 'westeurope');
    low_read_complex(group => 'openqa-rg', region => 'easteurope');
    low_read(group => 'openqa-rg', region => 'brazil');
    low_loop(group => 'openqa-rg',
        region => 'westeurope');
}