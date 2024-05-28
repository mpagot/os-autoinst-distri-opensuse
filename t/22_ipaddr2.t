use strict;
use warnings;
use Test::More;
use Test::Exception;
use Test::Warnings;
use Test::MockModule;
use Test::Mock::Time;
use List::Util qw(any none);

use sles4sap::ipaddr2;

subtest '[ipaddr2_azure_deployment]' => sub {
    my $ipaddr2 = Test::MockModule->new('sles4sap::ipaddr2', no_auto => 1);
    $ipaddr2->redefine(get_current_job_id => sub { return 'Volta'; });
    my @calls;
    $ipaddr2->redefine(assert_script_run => sub { push @calls, ['ipaddr2', $_[0]]; return; });
    $ipaddr2->redefine(data_url => sub { return '/Faggin'; });

    my $azcli = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);
    $azcli->redefine(assert_script_run => sub { push @calls, ['azure_cli', $_[0]]; return; });
    $azcli->redefine(script_output => sub { push @calls, ['azure_cli', $_[0]]; return 'Fermi'; });

    ipaddr2_azure_deployment(region => 'Marconi', os => 'Meucci');

    for my $call_idx (0 .. $#calls) {
        note("sles4sap::" . $calls[$call_idx][0] . " C-->  $calls[$call_idx][1]");
    }
    ok $#calls > 0, "There are some command calls";
};

subtest '[ipaddr2_ssh_cmd]' => sub {
    my $ipaddr2 = Test::MockModule->new('sles4sap::ipaddr2', no_auto => 1);
    $ipaddr2->redefine(get_current_job_id => sub { return 'Volta'; });

    my @calls;
    my $azcli = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);
    #$azcli->redefine(assert_script_run => sub { push @calls, ['azure_cli', $_[0]]; return; });
    $azcli->redefine(script_output => sub { push @calls, ['azure_cli', $_[0]]; return 'Fermi'; });

    my $ret = ipaddr2_ssh_cmd();

    for my $call_idx (0 .. $#calls) {
        note("sles4sap::" . $calls[$call_idx][0] . " C-->  $calls[$call_idx][1]");
    }

    like($ret, qr/ssh cloudadmin\@Fermi/, "The ssh command is like $ret");
};

subtest '[ipaddr2_destroy]' => sub {
    my $ipaddr2 = Test::MockModule->new('sles4sap::ipaddr2', no_auto => 1);
    $ipaddr2->redefine(get_current_job_id => sub { return 'Volta'; });
    my @calls;
    $ipaddr2->redefine(assert_script_run => sub { push @calls, $_[0]; return; });

    ipaddr2_destroy();

    note("\n  -->  " . join("\n  -->  ", @calls));
    ok((any { /az group delete/ } @calls), 'Correct composition of the main command');
};

subtest '[ipaddr2_deployment_sanity] Pass' => sub {
    my $ipaddr2 = Test::MockModule->new('sles4sap::ipaddr2', no_auto => 1);
    my @calls;
    $ipaddr2->redefine(script_run => sub { push @calls, ['ipaddr2', $_[0]]; return; });
    $ipaddr2->redefine(get_current_job_id => sub { return 'Volta'; });
    $ipaddr2->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });

    my $azcli = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);


    $azcli->redefine(script_output => sub {
            push @calls, ['azure_cli', $_[0]];
            # Simulate az cli to return 2 resource groups
            # one for the current jobId Volta and another one
            if ($_[0] =~ /az group list*/) { return '["ip2tVolta","ip2tFermi"]'; }
            # Simulate az cli to return exactly one name for the bastion VM name
            if ($_[0] =~ /az vm list*/) { return '["ip2t-vm-bastion", "ip2t-vm-01", "ip2t-vm-02"]'; }
            if ($_[0] =~ /az vm get-instance-view*/) { return '[ "PowerState/running", "VM running" ]'; }
    });

    ipaddr2_deployment_sanity();

    for my $call_idx (0 .. $#calls) {
        note("sles4sap::" . $calls[$call_idx][0] . " C-->  $calls[$call_idx][1]");
    }
    ok 1;
};

subtest '[ipaddr2_deployment_sanity] Fails rg num' => sub {
    my $ipaddr2 = Test::MockModule->new('sles4sap::ipaddr2', no_auto => 1);
    my @calls;
    $ipaddr2->redefine(script_run => sub { push @calls, ['ipaddr2', $_[0]]; return; });
    $ipaddr2->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });

    my $azcli = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);

    # Simulate az cli to return 2 resource groups
    # one for the current jobId Volta and another one
    $ipaddr2->redefine(get_current_job_id => sub { return 'Majorana'; });
    $azcli->redefine(script_output => sub {
            push @calls, ['azure_cli', $_[0]];
            if ($_[0] =~ /az group list*/) { return '["ip2tVolta","ip2tFermi"]'; }
            if ($_[0] =~ /az vm list*/) { return '["ip2t-vm-bastion"]'; }
    });

    dies_ok { ipaddr2_deployment_sanity() } "Sanity check if there's any rg with the expected name";

    for my $call_idx (0 .. $#calls) {
        note("sles4sap::" . $calls[$call_idx][0] . " C-->  $calls[$call_idx][1]");
    }
    ok scalar @calls > 0, "Some calls to script_run and script_output";
};

done_testing;
