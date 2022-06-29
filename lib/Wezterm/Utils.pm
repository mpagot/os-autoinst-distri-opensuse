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

sub switch_to_desktop {
    # switch to desktop
    if (!check_var('DESKTOP', 'textmode')) {
        select_console('x11', await_console => 0);
    }
}

# Install wezterm and set initial configuration
sub setup() {
    # log in to root console
    select_console('root-console');

    record_info('Initial Setup');

    zypper_call('in wezterm');
    assert_script_run('rpm -q wezterm');
}

# start Wezterm
sub start() {
    switch_to_desktop();
    x11_start_program('wezterm');
    wait_still_screen 5;
}

# quit Wezterm
sub quit() {
    send_key 'alt-f4';
}

# Open a new tab
sub new_tab() {
    send_key 'super-t';
}

# type something within Wezterm
sub send_string() {
    my ($self, $str) = @_;
    type_string $str;
    send_key 'ret';
    wait_still_screen 5;
}


1;
