# Copyright 2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# Summary: Select System Role 'Server' and navigate to next screen
# in openSUSE.
#
# Maintainer: QE YaST <qa-sle-yast@suse.de>

use strict;
use warnings;
use base 'y2_installbase';

sub run {
    $testapi::distri->get_system_role_controller()->select_system_role('server');
}

1;