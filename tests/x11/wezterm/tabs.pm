# SUSE's openQA tests
#
# Copyright 2021 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: Wezterm
# Summary: Wezterm regression test
# * install and configure wezterm
# Maintainer: QE Core <qe-core@suse.de>

use base "x11test";
use strict;
use warnings;
use testapi;
use Wezterm::Utils;
use utils;
use x11utils qw(turn_off_screensaver);

sub run() {
    my ($self) = shift;

    Wezterm::Utils->switch_to_desktop();
    Wezterm::Utils->start();
    Wezterm::Utils->new_tab();
    wait_still_screen 5;
    assert_screen([qw(wezterm two-tabs)], 10);
    Wezterm::Utils->quit();
}

1;