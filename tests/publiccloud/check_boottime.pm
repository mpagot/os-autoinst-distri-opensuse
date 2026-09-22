# SUSE's openQA tests
#
# Copyright 2026 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: Check the public cloud instance boot time against a threshold
# Maintainer: QE-C team <qa-c@suse.de>

use Mojo::Base 'publiccloud::basetest';
use testapi;
use Data::Dumper;
use Mojo::Util 'trim';
use publiccloud::utils qw(is_azure is_gce);
use publiccloud::ssh_interactive qw(select_host_console);
use version_utils qw(package_version_cmp);

sub systemd_time_to_second
{
    my $str_time = trim(shift);

    if ($str_time !~ /^(?<check_hour>(?<hour>\d{1,2})\s*h\s*)?(?<check_min>(?<min>\d{1,2})\s*min\s*)?((?<sec>\d{1,2}\.\d{1,3})s|(?<ms>\d+)ms)$/) {
        record_info("WARN", "Unable to parse systemd time '$str_time'", result => 'fail');
        return -1;
    }
    my $sec = $+{sec} // $+{ms} / 1000;
    $sec += $+{min} * 60 if (defined($+{check_min}));
    $sec += $+{hour} * 3600 if (defined($+{check_hour}));
    return $sec;
}

sub extract_analyze_time {
    my $str_time = shift;
    my $res = {};
    # Pick the line that actually holds the timing, not blindly the first line:
    # ssh_script_output may prepend an SSH login banner / MOTD, which would
    # otherwise leave us parsing an empty or non-timing line (poo#203817).
    ($str_time) = grep { /Startup finished in/i } split(/\r?\n/, $str_time);
    return undef unless defined($str_time);
    $str_time =~ s/Startup finished in\s*//i;
    $str_time =~ s/=(.+)$/+$1 (overall)/;
    for my $time (split(/\s*\+\s*/, $str_time)) {
        $time = trim($time);
        my ($time, $type) = $time =~ /^(.+)\s*\((\w+)\)$/;
        $res->{$type} = systemd_time_to_second($time);
        return undef if ($res->{$type} == -1);
    }
    foreach (qw(kernel initrd userspace overall)) { return undef unless exists($res->{$_}); }
    return $res;
}

sub extract_blame_time {
    my $str_time = shift;
    my $ret = {};
    for my $line (split(/\r?\n/, $str_time)) {
        $line = trim($line);
        # Only <time> <service> lines are blame entries; skip anything else
        # (e.g. an SSH login banner / MOTD prepended to the output, poo#203817).
        my ($time, $service) = $line =~ /^(\S+)\s+(\S+)$/;
        next unless defined($service);
        my $sec = systemd_time_to_second($time);
        next unless ($sec >= 0);
        $ret->{$service} = $sec;
    }
    return $ret;
}

sub do_systemd_analyze_time {
    my ($instance, %args) = @_;
    my $timeout = $args{timeout} // 300;
    my $start_time = time();
    my $output = "";
    my $finished = 0;
    my @ret;

    # Poll systemd-analyze until the system has actually finished booting.
    # On a freshly-launched Public Cloud instance SSH becomes reachable while
    # late boot units (e.g. cloud-init) are still running, so systemd-analyze
    # reports "Bootup is not yet finished (...FinishTimestampMonotonic=0)" and
    # exits non-zero (poo#203817). "Startup finished in" only appears once boot
    # is complete, so it is our readiness signal. Break out on the successful
    # match *before* sleeping so a result arriving near the timeout is not
    # discarded, and gate success on the match rather than on elapsed time.
    while (time() - $start_time < $timeout) {
        # calling systemd-analyze time
        $output = $instance->ssh_script_output(cmd => 'systemd-analyze time', proceed_on_failure => 1);
        if ($output =~ /Startup finished in/i) {
            $finished = 1;
            last;
        }
        sleep 5;
    }
    unless ($finished) {
        record_info("WARN", "Unable to get systemd-analyze in ${timeout}s.\nLast output:" . $output, result => 'fail');
        # List all jobs and the failed units to support debug the issue
        record_info("list-jobs", $instance->ssh_script_output(cmd => 'systemctl list-jobs --no-pager', proceed_on_failure => 1));
        record_info("failed units", $instance->ssh_script_output(cmd => 'systemctl --failed --no-pager', proceed_on_failure => 1));
        # guestregister.service getting stuck "running" is the usual reason bootup
        # never finishes (bsc#1264275), so dump its state and log to pinpoint where
        # it hangs.
        record_info("guestregister", $instance->ssh_script_output(cmd => 'systemctl status --no-pager --full guestregister.service', proceed_on_failure => 1));
        record_info("guestregister journal", $instance->ssh_script_output(cmd => 'sudo journalctl --no-pager -u guestregister.service | tail -n 100', proceed_on_failure => 1));
        record_info("cloudregister", $instance->ssh_script_output(cmd => 'sudo tail -n 100 /var/log/cloudregister', proceed_on_failure => 1));
        # On GCE the hang has been traced to gcemetadata never returning while
        # fetching the instance identity token; call it directly (bounded by a
        # timeout so we do not block the test) to confirm whether it is stuck.
        if (is_gce()) {
            record_info("gcemetadata", $instance->ssh_script_output(
                    cmd => 'sudo timeout 60 /usr/bin/gcemetadata --query instance --identity http://smt-gce.susecloud.net --identity-format full --identity-licenses TRUE --xml; echo "gcemetadata exit=$?"',
                    proceed_on_failure => 1, timeout => 90));
            # The hang is a known gcemetadata bug fixed in python-gcemetadata 1.1.2
            # (SUSE-Enceladus, "Address hang in dual stack set up"): on an
            # IPV4_IPV6 instance it connects to the DNS name
            # metadata.google.internal (injected into /etc/hosts), which blocks
            # for >40s, and its urlopen had no timeout. Record the installed
            # version so a pre-fix image can be told apart from a real outage.
            # Read the version from RPM only: do NOT run `gcemetadata --version`,
            # because the CLI builds the GCEMetadata object (which runs the
            # connectivity probe) before printing the version, so on a pre-1.1.2
            # dual-stack instance it hangs, blows the script timeout, wedges the
            # serial console and cascades into every following module dying at
            # console setup ("script timeout: hostname"). rpm never touches
            # gcemetadata and cannot hang.
            record_info("gcemetadata version", $instance->ssh_script_output(
                    cmd => 'rpm -q python-gcemetadata || rpm -qf "$(readlink -f /usr/bin/gcemetadata)"',
                    proceed_on_failure => 1));
            # Reproducer: even the trivial `gcemetadata --version` hangs on a
            # pre-1.1.2 dual-stack instance. The CLI builds the GCEMetadata
            # object first, and its __init__ calls get_available_api_versions()
            # -> _get() -> urllib.request.urlopen() with no timeout against the
            # metadata DNS name, which prefers the unrouted IPv6 address and
            # blocks ~40s -- all *before* the version is ever printed. Bound it
            # hard with a shell `timeout` (and a matching script timeout) so this
            # reproducer can NEVER wedge the serial console: exit 124 == it hung
            # == the bug is present; a fast exit 0 == fixed (>= 1.1.2).
            record_info("gcemetadata --version", $instance->ssh_script_output(
                    cmd => 'timeout 60 /usr/bin/gcemetadata --version; echo "gcemetadata --version exit=$?"',
                    proceed_on_failure => 1, timeout => 90));
            # Show how the metadata server name resolves under dual-stack, which
            # is the input that makes the pre-1.1.2 connect() hang.
            record_info("metadata hosts", $instance->ssh_script_output(
                    cmd => 'grep -E "metadata.google.internal|susecloud" /etc/hosts; echo ---; getent ahosts metadata.google.internal',
                    proceed_on_failure => 1));
            # Compare reaching the metadata server by literal IPv4 / IPv6 address
            # (what the 1.1.2 fix does) vs. by DNS name (the path that hangs). A
            # fast IP response next to a slow/absent name response confirms the
            # dual-stack DNS hang rather than an unreachable metadata service.
            record_info("metadata by addr", $instance->ssh_script_output(
                    cmd => 'for t in "169.254.169.254" "[fd20:ce::254]" "metadata.google.internal"; do '
                      . 'echo "== $t =="; timeout 15 curl -sS -o /dev/null '
                      . '-w "http_code=%{http_code} time_total=%{time_total}\n" '
                      . '-H "Metadata-Flavor: Google" "http://$t/computeMetadata/v1/instance/id" '
                      . '|| echo "exit=$? (timed out or failed)"; done',
                    proceed_on_failure => 1, timeout => 90));
        }
        return (0, 0);
    }
    # log time
    $instance->ssh_script_run("uptime");

    push @ret, extract_analyze_time($output);

    $output = $instance->ssh_script_output(cmd => 'systemd-analyze blame', proceed_on_failure => 1);
    push @ret, extract_blame_time($output);

    return @ret;
}

=head2 is_first_boot

    is_first_boot($instance);

Return true the first time this is called for a given instance, tracked via a marker file left on the instance (the journal is volatile on public cloud images, so C<journalctl --list-boots> cannot be used to detect earlier boots).

=cut

sub is_first_boot {
    my ($instance) = @_;
    my $marker = '/root/openqa_boottime_seen';
    return 0 if ($instance->ssh_script_run(cmd => "sudo test -e $marker", proceed_on_failure => 1) == 0);
    $instance->ssh_script_run(cmd => "sudo touch $marker", proceed_on_failure => 1);
    return 1;
}

=head2 check_system_boottime

    check_system_boottime($instance);

Wait for the instance to finish booting (via C<systemd-analyze time>) and
record the timing, acting as a readiness gate for whatever runs after this
module (poo#203817, poo#204852, poo#205311). When C<PUBLIC_CLOUD_BOOTTIME_MAX>
is set, also fail the job if the measured boot time exceeds it. Diagnostic
logs are collected only on the first boot.

=cut

sub check_system_boottime {
    my ($instance, %args) = @_;
    my $max_boot_time = get_var('PUBLIC_CLOUD_BOOTTIME_MAX');
    my $first_boot = is_first_boot($instance);

    my $ret = {
        kernel_release => undef,
        kernel_version => undef,
        type => 'boottime',
        analyze => {},
        blame => {},
    };

    record_info("BOOT TIME", 'systemd_analyze');
    # first deployment analysis
    my ($systemd_analyze, $systemd_blame) = do_systemd_analyze_time($instance, %args);
    unless ($systemd_analyze && $systemd_blame) {
        # Boot never finished. On Public Cloud the usual reason is that
        # guestregister.service is still running, but "stuck guestregister" is
        # only a symptom and has more than one root cause - do not collapse them
        # onto a single bug:
        #
        #  * bsc#1264275 is the server-side SCC regsharing race. Its specific
        #    fingerprint is an HTTP 422 in /var/log/cloudregister ("Could not
        #    announce system ... already taken" / "Unprocessable Entity"), NOT
        #    merely a guestregister job in "running" state.
        #  * A hung registration call also leaves guestregister running, but with
        #    NO 422 logged. On GCE this is the dual-stack gcemetadata stall
        #    (bsc#1277388): python-gcemetadata < 1.1.2 connects to the metadata
        #    server over its preferred-but-unrouted IPv6 address and blocks ~40s
        #    per call, so registration/boot never finishes. It is a different bug
        #    and must not be mislabelled as bsc#1264275.
        #  * Do not confuse either with bsc#1246104, whose title matches the
        #    symptom but not the root cause here.
        #
        # So gate the soft-failure on the 422 signature, not on the job state.
        my $cloudregister = $instance->ssh_script_output(cmd => 'sudo cat /var/log/cloudregister', proceed_on_failure => 1);
        my ($scc_422) = $cloudregister =~ /^(.*(?:Could not announce system|already taken|Unprocessable Entity).*\(422\).*)$/m;
        my $guestregister_running = $instance->ssh_script_output(cmd => 'sudo systemctl list-jobs', proceed_on_failure => 1) =~ /guestregister\.service\s+start\s+running/;

        if (defined($scc_422)) {
            record_info("SCC 422", $scc_422, result => 'fail');
            record_soft_failure("bsc#1264275 - SCC returned 422 (regsharing race), registration never finished so boot time cannot be measured");
            return;
        } elsif ($guestregister_running) {
            # guestregister wedged without a 422: this is NOT bsc#1264275. Surface
            # the cloudregister tail so the real culprit is visible.
            record_info("cloudregister", $cloudregister, result => 'fail');
            # On GCE the known culprit is the dual-stack gcemetadata stall fixed
            # in python-gcemetadata 1.1.2. Detect a pre-fix package (e.g. 1.1.1)
            # and soft-fail with the matching bug instead of dying.
            if (is_gce()) {
                my $gcever = trim($instance->ssh_script_output(cmd => q(rpm -q --qf '%{VERSION}' python-gcemetadata), proceed_on_failure => 1));
                if ($gcever =~ /^\d+(?:\.\d+)*$/ && package_version_cmp($gcever, '1.1.2') < 0) {
                    record_info("gcemetadata", "python-gcemetadata $gcever < 1.1.2 (pre dual-stack fix)", result => 'fail');
                    record_soft_failure("bsc#1277388 - dual-stack gcemetadata stall (python-gcemetadata $gcever < 1.1.2), registration never finished so boot time cannot be measured");
                    return;
                }
            }
            die("guestregister.service stuck without an SCC 422 - boot never finished; not bsc#1264275, see cloudregister log and gcemetadata diagnostics");
        } else {
            die("failed to obtain boottime from systemd");
        }
    }

    $ret->{analyze}->{$_} = $systemd_analyze->{$_} foreach (keys(%{$systemd_analyze}));
    $ret->{blame} = $systemd_blame;
    my $boottime = $ret->{analyze}->{overall};

    # Collect kernel version
    $ret->{kernel_release} = $instance->ssh_script_output(cmd => 'uname -r', proceed_on_failure => 1);
    $ret->{kernel_version} = $instance->ssh_script_output(cmd => 'uname -v', proceed_on_failure => 1);

    $Data::Dumper::Sortkeys = 1;
    record_info("RESULTS", Dumper($ret));
    if ($first_boot) {
        my $dir = "/var/log";
        my @logs = qw(cloudregister cloud-init.log cloud-init-output.log messages NetworkManager);
        $instance->upload_check_logs_tar(map { "$dir/$_" } @logs);
    }

    # Boot time overall limit check, only when a threshold is configured
    return unless ($max_boot_time);
    if ($boottime > $max_boot_time) {
        if (is_azure()) {
            # Unreliable userspace boot time in Azure.
            record_soft_failure("bsc#1262587 - openQA publiccloud tests have anomalous-high boot-time from systemd-analyze");
        } else {
            # threshold exceeded
            die("System boot time overall $boottime is out of limit $max_boot_time");
        }
    }
}

sub run {
    my ($self, $args) = @_;

    select_host_console();    # select console on the host, not the PC instance

    check_system_boottime($args->{my_instance});
}

sub test_flags {
    return {fatal => 0};
}

1;
