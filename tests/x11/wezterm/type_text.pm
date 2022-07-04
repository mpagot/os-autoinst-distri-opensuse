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
    $self->test_terminal('wezterm');

    Wezterm::Utils->start();
    Wezterm::Utils->send_string('echo "Hello World"');
    assert_screen('hello-world', 10);
    Wezterm::Utils->send_string('echo "USER:$USER"');
    Wezterm::Utils->send_string('echo "HOME:$HOME"');
    Wezterm::Utils->send_string('wezterm -V');
    Wezterm::Utils->send_string('which wezterm');

    Wezterm::Utils->quit();
}

1;