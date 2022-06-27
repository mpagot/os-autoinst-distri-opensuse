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
use version_utils 'is_sle';
use x11utils qw(turn_off_screensaver);

sub run() {

    my ($self) = shift;
    # install and configure wezterm in console
    Wezterm::Utils->wezterm_setup();

    # switch to desktop
    $self->switch_to_desktop();

    # start wezterm
    $self->turn_off_screensaver();

    # switch to desktop
    $self->switch_to_desktop();
}

sub switch_to_desktop {
    # switch to desktop
    if (!check_var('DESKTOP', 'textmode')) {
        select_console('x11', await_console => 0);
    }
}

1;
