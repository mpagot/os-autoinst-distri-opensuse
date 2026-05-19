# SUSE's openQA tests
#
# Copyright 2021 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: rear23a
# Summary: Restore a ReaR backup
# Maintainer: QE-SAP <qe-sap@suse.de>, Loic Devulder <ldevulder@suse.com>

use Mojo::Base 'rear';
use testapi;
use serial_terminal 'select_serial_terminal';
use power_action_utils 'power_action';
use Utils::Architectures;

sub run {
    my ($self) = @_;
    my $hostname = get_var('HOSTNAME', 'susetest');
    my $timeout = bmwqemu::scale_timeout(600);

    # Select recovering entry and wait for OS boot
    assert_screen('rear-boot-screen');
    send_key_until_needlematch('rear-recover-selected', 'up');
    send_key 'ret';

    # Handle the output error about busy tty0 in ppc64
    if (is_ppc64le) {
        check_screen('rear_restore-tty-20241105', 120);
        send_key 'ret';
        type_string("root\n");
        wait_still_screen(3);
        type_string("clear\n");
    }
    else {
        $self->wait_boot_past_bootloader;
    }

    # Restore the OS backup
    set_var('LIVETEST', 1);    # Because there is no password in ReaR miniOS
    select_console('root-console', skip_setterm => 1);    # Serial console is not configured in ReaR miniOS
    $self->upload_fs_blk_info(prefix => 'before');
    assert_script_run('set -o pipefail');

    # Workaround for ReaR pipe-hang bug (bsc#XXXX / https://github.com/rear/rear/issues/XXXX):
    # ReaR's _framework-setup-and-functions.sh saves stdout/stderr as fd7/fd8
    # ("exec 7>&1; exec 8>&2"). When running "rear ... |& tee", fd7/fd8 point to the
    # pipe. Daemons started by ReaR (rpcbind, rpc.statd) inherit these fds; their
    # daemon(0,0) only closes fd 0/1/2, so fd7/fd8 keep the pipe open. tee never gets
    # EOF -> pipeline hangs -> test timeout.
    #
    # After rear exits, the diagnostic wrapper identifies pipe WRITE-end holders
    # (offending daemons), logs proof, and kills them so tee gets EOF.
    my $diag_log = '/var/log/rear-pipe-diag.log';
    my $rear_rc_file = '/tmp/rear-exit-code';
    my $cmd = 'export USER_INPUT_TIMEOUT=5; '
      . '{ rear -d -D recover; RC=$?; '
      . 'echo $RC > ' . $rear_rc_file . '; '
      . 'D=' . $diag_log . '; '
      . 'echo "=== DIAGNOSTIC: ReaR fd7/fd8 pipe leak ===" > $D; '
      . 'echo "rear_exit_code=$RC" >> $D; '
      . 'date "+%Y-%m-%d %H:%M:%S" >> $D; '
      . 'echo "" >> $D; '
      # Identify the pipe inode from our subshell's stdout (fd1 inside { } goes to tee)
      . 'MY_PID=$BASHPID; '
      . 'PIPE=$(readlink /proc/$MY_PID/fd/1); '
      . 'echo "subshell_pid=$MY_PID pipe=$PIPE" >> $D; '
      # Scan for WRITE-end pipe holders (ls -la shows 'l-wx' for write, 'lr-x' for read)
      # This safely excludes tee (read-end holder) without relying on PID matching
      . 'echo "" >> $D; '
      . 'echo "## Pipe write-end holders (offenders):" >> $D; '
      . 'FOUND=0; '
      . 'for p in /proc/[0-9]*; do '
      . '  PID=${p#/proc/}; '
      . '  [ "$PID" = "$MY_PID" ] && continue; '
      . '  if ls -la $p/fd 2>/dev/null | grep -F "$PIPE" | grep -q "^l-wx"; then '
      . '    FOUND=1; '
      . '    CMD=$(cat $p/cmdline 2>/dev/null | tr "\\0" " "); '
      . '    echo "  PID=$PID CMD=[$CMD]" >> $D; '
      . '    for fd in $p/fd/*; do '
      . '      FD_NUM=${fd##*/}; '
      . '      FD_TARGET=$(readlink $fd 2>/dev/null); '
      . '      [ "$FD_TARGET" = "$PIPE" ] && echo "    fd $FD_NUM -> $FD_TARGET" >> $D; '
      . '    done; '
      . '  fi; '
      . 'done; '
      . '[ $FOUND -eq 0 ] && echo "  (none found)" >> $D; '
      . 'echo "" >> $D; '
      # Kill only WRITE-end holders to unblock tee
      . 'echo "## Killing write-end holders:" >> $D; '
      . 'for p in /proc/[0-9]*; do '
      . '  PID=${p#/proc/}; '
      . '  [ "$PID" = "$MY_PID" ] && continue; '
      . '  if ls -la $p/fd 2>/dev/null | grep -F "$PIPE" | grep -q "^l-wx"; then '
      . '    CMD=$(cat $p/cmdline 2>/dev/null | tr "\\0" " "); '
      . '    echo "  kill $PID [$CMD]" >> $D; '
      . '    kill $PID 2>/dev/null; '
      . '  fi; '
      . 'done; '
      . 'echo "=== END ===" >> $D; '
      . 'exit $RC; } '
      . '|& tee -a ' . $self->rear_cmd_log();
    # Use script_run (not assert_script_run) so we can upload logs before checking
    # the exit code. The pipeline may return non-zero due to the pipe-holder kill
    # workaround, even when rear itself succeeded.
    my $ret = script_run($cmd, timeout => $timeout);
    upload_logs($diag_log, failok => 1);
    $self->upload_rear_logs;
    # Check rear's actual exit code (written to file before diagnostic runs)
    my $rear_rc = script_run("cat $rear_rc_file && test \$(cat $rear_rc_file) -eq 0");
    die "rear recover failed (exit code in $rear_rc_file)" if $rear_rc;
    die "rear recover timed out (pipeline hung for ${timeout}s)" unless defined $ret;
    set_var('LIVETEST', 0);

    # Reboot into the restored OS
    power_action('reboot', keepconsole => 1);
    $self->wait_boot;

    # Test login to ensure that the based OS configuration is correctly restored
    select_serial_terminal;
    assert_script_run('cat /etc/os-release ; uname -a');
}

1;
