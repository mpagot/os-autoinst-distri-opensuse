# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# Summary: testapi stress test
# Maintainer: none

=head1 NAME

longoutput.pm - Execute testapi stress tests 

=head1 DESCRIPTION

Stress test for script_run, script_output and script_retry.
Supports two modes: 'stress' (looping with increasing sizes) and 'repro' (targeted 10MB dump).

=head1 SETTINGS

=over

=item B<LO_TEST_TYPE>

'stress' (default) or 'repro'.

=item B<LO_OUTPUT_SIZE>, B<LO_OUTPUT_SCALE>, B<LO_OUTPUT_LOOPS>, B<LO_OUTPUT_SLEEP>

Used in 'stress' mode.

=item B<LO_REPRO_SIZE>

Used in 'repro' mode (defaults to 10MB).

=item B<LO_COLLECT_TERM_INFO>

If set, collects stty/tty info before/after operations.

=back

=cut

use Mojo::Base 'publiccloud::basetest';
use testapi;
use serial_terminal qw( select_serial_terminal );
use utils qw(script_retry);
use Digest::MD5 qw(md5_hex);

sub record_terminal_info {
    my ($label) = @_;
    my $stty = script_output("stty -a");
    my $tty = script_output("tty");
    my $term = script_output("echo \$TERM");
    my $ps1 = script_output("echo \$PS1");
    record_info("Term $label", "TTY: $tty\nTERM: $term\nPS1: $ps1\nSTTY:\n$stty");
}

sub create_test_file {
    my ($size, $filename, $timeout) = @_;
    my $chars = 'A-Za-z0-9\$\`&|\\\\\"\\n';
    script_run("(set +o pipefail; tr -dc '$chars' < /dev/urandom | head -c $size > $filename)", timeout => $timeout);
    my $sut_md5 = script_output("md5sum $filename | cut -d' ' -f1");
    my $sut_size = script_output("stat -c%s $filename");
    return ($sut_md5, $sut_size);
}

sub verify_integrity {
    my ($captured, $sut_md5, $sut_size) = @_;
    my $perl_md5 = md5_hex($captured // '');
    if ($perl_md5 eq $sut_md5) {
        record_info("Match OK", "Size: " . length($captured // ''));
        return 1;
    } else {
        record_info("MD5 MISMATCH", "SUT: $sut_md5 (size $sut_size)\nPerl: $perl_md5 (size " . length($captured // '') . ")", result => 'fail');
        return 0;
    }
}

sub run_stress {
    my ($self) = @_;
    my $len = get_required_var('LO_OUTPUT_SIZE');
    my $scale = get_required_var('LO_OUTPUT_SCALE');
    my $loops = get_required_var('LO_OUTPUT_LOOPS');
    my $sleep_time = get_required_var('LO_OUTPUT_SLEEP');
    my $guard = 'echo "STILL STANDING"';

    for my $i (0..$loops) {
        my $size = $len * $scale * $i;
        my $timeout = int($size / 50000) + 60;
        my $filename = "/tmp/stress_data_$i.bin";

        script_run("echo 'i:$i size:$size'");
        record_terminal_info("Post script_run i:$i");

        my ($sut_md5, $sut_size) = create_test_file($size, $filename, $timeout);
        record_info("SUT Stats i:$i", "Size: $sut_size, MD5: $sut_md5");

        # -- test script_run with zero --
        script_run("head -c $size /dev/zero");
        script_run($guard);
        sleep $sleep_time;

        # -- test script_run --
        script_run("cat $filename", timeout => $timeout);
        script_run($guard);
        sleep $sleep_time;

        # -- test script_output --
        my $captured = script_output("cat $filename", timeout => $timeout);
        script_run($guard);
        sleep $sleep_time;

        # -- test script_retry --
        script_retry("cat $filename", timeout => $timeout, retry => 2, die => 0);
        script_run($guard);
        sleep $sleep_time;

        record_terminal_info("Post script_output i:$i");
        script_output("dmesg | grep -i overrun || echo 'No overruns'");
        verify_integrity($captured, $sut_md5, $sut_size);
        script_run("rm $filename");
        sleep $sleep_time;
    }
}

sub run_repro {
    my ($self) = @_;
    my $size = get_var('LO_REPRO_SIZE', 10 * 1024 * 1024); # Default 10MB
    my $timeout = int($size / 50000) + 60;
    my $filename = "/tmp/repro.bin";
    my $guard = "echo 'ALIVE'";

    record_info("Repro", "Starting repro with $size bytes output");

    my ($sut_md5, $sut_size) = create_test_file($size, $filename, $timeout);
    record_terminal_info("Initial Repro");

    record_info("Test", "Running script_run(cat $filename)");
    script_run("cat $filename", timeout => $timeout);
    record_terminal_info("Post script_run");

    # Check if next command works
    record_info("Test", "Running next command (guard)");
    script_run($guard, timeout => 60);
    record_terminal_info("Post guard");

    # Dump it with script_output
    record_info("Test", "Running script_output(cat $filename)");
    my $captured = script_output("cat $filename", timeout => $timeout);
    record_terminal_info("Post script_output");
    verify_integrity($captured, $sut_md5, $sut_size);

    script_run("rm $filename");
}

sub run {
    my ($self) = @_;
    select_serial_terminal;
    
    my $type = get_var('LO_TEST_TYPE', 'stress');
    
    if ($type eq 'repro') {
        $self->run_repro();
    } else {
        $self->run_stress();
    }
}

sub test_flags {
    return {fatal => 1};
}

1;
