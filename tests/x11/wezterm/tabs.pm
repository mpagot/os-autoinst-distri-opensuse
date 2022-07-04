# SUSE's openQA tests
#
# Copyright 2021 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: Wezterm
# Summary: Wezterm regression test
# * open new tab
# Maintainer: QE Core <qe-core@suse.de>

use base "x11test";
use strict;
use warnings;
use testapi;
use Wezterm::Utils;

sub run() {
    my ($self) = shift;

    # Test with the default key binding
    Wezterm::Utils->test_new_tab();
    wait_still_screen 5;

    # Test new tab with some custom key binding
    Wezterm::Utils->test_new_tab_key_binding(key => 'w');
    Wezterm::Utils->test_new_tab_key_binding(key => 'n');
}

1;