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

sub run() {
    my ($self) = shift;

    my @locations = ( ['$HOME', '.wezterm.lua'],
                      ['$HOME/.config/wezterm', 'wezterm.lua'],
                      ['$XDG_CONFIG_HOME/wezterm', 'wezterm.lua'] 
                      );
    for my $ref (@locations) {
        # Test new tab with some custom key binding
        Wezterm::Utils->test_new_tab_key_binding(key => 'w', cfg_dir => @$ref[0], cfg_filename => @$ref[1]);
    }
}

1;