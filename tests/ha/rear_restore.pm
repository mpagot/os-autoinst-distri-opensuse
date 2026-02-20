# SUSE's openQA tests
#
# Copyright 2021 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: rear23a
# Summary: Restore a ReaR backup
# Maintainer: QE-SAP <qe-sap@suse.de>, Loic Devulder <ldevulder@suse.com>

use base 'rear';
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

    script_run 'ip a show lo';

    script_run 'ls -lai /bin | grep -E "rear|rpcbind|rpm|zypper"';
    script_run 'ls -lai /sbin | grep -E "rear|rpcbind|rpm|zypper"';
    script_run 'ls -lai /usr/bin | grep -E "rear|rpcbind|rpm|zypper"';
    script_run 'echo "__${PATH}__"';
    script_run 'which rpcbind';
    script_run 'which rpm';
    script_run 'which zypper';
    script_run 'rpm -q rpcbind';
    script_run 'zypper se -s -i  rpcbind';
    script_run '/bin/rpcbind -h';
    script_run '/bin/rpcbind -v';
    script_run 'ldd /bin/rpcbind';

    # Check SLES 16 /usr/etc migration impact on rpcbind and sshd
    script_run 'ls -l /usr/etc/nsswitch.conf /etc/nsswitch.conf';
    script_run 'grep "services:" /usr/etc/nsswitch.conf /etc/nsswitch.conf';
    # Check for library required by "services: files usrfiles" in nsswitch.conf
    script_run 'ls -l /lib64/libnss_usrfiles.so* /usr/lib64/libnss_usrfiles.so*';
    script_run 'ls -l /usr/etc/services /etc/services';
    script_run 'head -n 3 /etc/services';

    script_run 'ls -l /usr/etc/ssh/sshd_config /etc/ssh/sshd_config';
    script_run 'ls -l /usr/libexec/openssh/sshd-auth';

    # Check rpcbind dependencies and runtime
    script_run 'ls -l /etc/netconfig /etc/bindresvport.conf';
    script_run 'id rpc';
    script_run 'ls -ld /run /var/run';

    # Start rpcbind as a daemon (no -f) so it does not block the shell
    script_run '/bin/rpcbind -w';
    # Verify if it is actually running and registering RPC services
    script_run 'ps -C rpcbind';
    script_run 'rpcinfo -p > /tmp/rpcinfo_manual.log 2>&1';
    script_run 'cat /tmp/rpcinfo_manual.log';
    upload_logs '/tmp/rpcinfo_manual.log';

    # Simulate the failing check from ReaR's 050_start_required_nfs_daemons.sh
    # This helps confirm if the environment/rpcinfo output is the cause
    script_run 'if rpcinfo -p | grep -q "portmapper"; then echo "Simulated ReaR check: SUCCESS (portmapper found)"; else echo "Simulated ReaR check: FAIL (portmapper NOT found)"; fi';

    # Also log the status of nss libraries
    script_run 'ls -l /lib*/libnss_usrfiles* /usr/lib*/libnss_usrfiles*';

    assert_script_run('export USER_INPUT_TIMEOUT=5; rear -v -d -D recover', timeout => $timeout);
    $self->upload_rear_logs;
    set_var('LIVETEST', 0);

    # Reboot into the restored OS
    power_action('reboot', keepconsole => 1);
    $self->wait_boot;

    # Test login to ensure that the based OS configuration is correctly restored
    select_serial_terminal;
    assert_script_run('cat /etc/os-release ; uname -a');
}

1;
