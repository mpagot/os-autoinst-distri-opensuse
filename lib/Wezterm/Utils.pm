# SUSE's openQA tests
#
# Copyright 2021 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: Provide functionality for wezterm installation and configuration.
# Maintainer: QE Core <qe-core@suse.de>

package Wezterm::Utils;
use base "x11test";
use strict;
use warnings;
use testapi;
use utils;


# Install wezterm and set initial configuration
sub wezterm_setup() {
    # log in to root console
    select_console('root-console');

    record_info('Initial Setup');

    zypper_call('in wezterm');
    assert_script_run('rpm -q wezterm');
}


1;
