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
    # install and configure wezterm in console
    Wezterm::Utils->setup();

    Wezterm::Utils->switch_to_desktop();
    $self->turn_off_screensaver();
}

1;