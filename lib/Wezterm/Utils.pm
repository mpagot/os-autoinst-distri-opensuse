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

# check if in the input string there's something like an ENV variable
# and check if it is defined or not
sub check_env() {
    my ($self, $env) = @_;
    my @captured = $env =~ /\$\{?([a-zA-Z0-9\-_]+)\}?/g;
    if( @captured ) {
        foreach (@captured) {
            assert_script_run('[ -n "${' . $_ .'}" ]');
        }
    }
}

# Get a folder and a file strings for the wezterm.lua configuration file
# For each of the two strings it checks if they are composed by a not 
# expanded environment variable and checks if the variable exists
# in the SUT environment.
# Return a joined string with full wezterm config file path
sub validate_config_destination_path() {
    my ($self) = shift;
    my ($cfg_dir) = shift;
    my ($cfg_filename) = shift;

    $self->check_env($cfg_dir);
    $self->check_env($cfg_filename);
    return $cfg_dir . '/' . $cfg_filename;
}


# Get a pre-cooked wezterm.lua from data/wezterm to
# the appropriate place.
# https://wezfurlong.org/wezterm/config/files.html
sub activate_config() {
    my ($self) = shift;
    my ($config) = shift;
    my %args = @_;
    my $cfg_dir = $args{cfg_dir} || '$HOME';
    my $cfg_filename = $args{cfg_filename} || '.wezterm.lua';

    select_console('user-console');

    my $cfg_file = $self->validate_config_destination_path($cfg_dir, $cfg_filename);

    assert_script_run('cd $HOME');
    assert_script_run('rm ' . $cfg_file . ' || echo "Nothing to delete"');
    assert_script_run('mkdir -p ' . $cfg_dir . ' || echo "Nothing to make"');
    assert_script_run('curl -o ' . $cfg_file . ' ' . data_url("wezterm/$config/wezterm.lua"));
    assert_script_run('ls -lai ' . $cfg_dir);
    assert_script_run('cat ' . $cfg_file);
}


# start Wezterm
sub start() {
    my ($self) = @_;
    $self->switch_to_desktop();
    x11_start_program('wezterm');
    wait_still_screen 5;
}

# quit Wezterm
sub quit() {
    send_key 'alt-f4';
    wait_still_screen;
    assert_screen("generic-desktop");
    #select_console('user-console');
    #die 'Wezterm should not be running!' if (script_output('ps aux|grep wezterm|grep -v grep|wc -l') != 0);
}

# type something within Wezterm
sub send_string() {
    my ($self, $str) = @_;
    type_string $str;
    send_key 'ret';
    wait_still_screen 5;
}

# Open a new tab
sub new_tab() {
    send_key 'super-t';
}

sub test_new_tab() {
    my ($self) = shift;
    $self->switch_to_desktop();

    # Test with the default key binding
    $self->start();
    $self->new_tab();
    wait_still_screen 5;
    assert_screen('two-tabs', 10);
    $self->quit();
}

# Provide a template file, from the assets folder (data)
# a KEY:VALUE pair ( a single one for the moment)
# This function read, edit and write the wezterm.cfg in $cfg_dir/$cfg_file
sub write_config_from_template() {
    my ($self) = shift;
    my %args = @_;
    my $template_key = $args{template_key} || die 'Missing template key';
    my $template_value = $args{template_value} || die 'Missing value to substitute in the template';
    my $template = $args{template} || die 'Missing template';

    # Destination in the SUT
    my $cfg_dir = $args{cfg_dir} || '$HOME';
    my $cfg_filename = $args{cfg_filename} || '.wezterm.lua';
    select_console('user-console');
    my $cfg_file = $self->validate_config_destination_path($cfg_dir, $cfg_filename);

    # Source from test assets
    my $cfg_content = get_test_data($template);
    $cfg_content =~ s/\{\{$template_key\}\}/$template_value/g;
    save_tmp_file($template, $cfg_content);
    assert_script_run('curl -o ' . $cfg_file . ' ' . autoinst_url . "/files/$template");
    assert_script_run('test -e ' . $cfg_file . ' && cat ' . $cfg_file);
    record_info($cfg_file, $cfg_content);
    return $cfg_file;
}


sub test_new_tab_key_binding() {
    my ($self) = shift;
    my %args = @_;
    my $key = $args{key} || 'w';

    # Destination in the SUT
    my $cfg_dir = $args{cfg_dir} || '$HOME';
    my $cfg_filename = $args{cfg_filename} || '.wezterm.lua';

    # Source from test assets
    my $cfg_dir = 'new_tab_key_parametric';
    my $cfg = "wezterm/$cfg_dir/wezterm.lua";

    my $cfg_file = $self->write_config_from_template(template => $cfg, template_key => 'NEW_TAB_KEY', template_value => $key, cfg_dir => $cfg_dir, cfg_filename => $cfg_filename);

    $self->switch_to_desktop();
    $self->start();

    #Test at first the custom key configured in the wezterm.lua
    send_key "super-$key";
    if ( check_screen('two-tabs', 10) ) {
        record_info('NEW_TAB_MATCH', "super-$key is able to open a new tab");
    }
    else
    {
        record_soft_failure("New tab not opened by 'super-$key' configured by config placed at $cfg_file");
        # In case of failure try the default
        $self->new_tab();
        if ( check_screen('two-tabs', 10) ) {
            record_info('NEW_TAB_MATCH', "super-t is able to open a new tab");
        }
        else
        {
            record_soft_failure("New tab not opened by 'super-t' configured by config placed at $cfg_file");
        }
    }
    $self->quit();
    select_console('user-console');
    assert_script_run("rm $cfg_file");
}

1;
