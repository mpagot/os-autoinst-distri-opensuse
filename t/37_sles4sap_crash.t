use strict;
use warnings;
use Test::More;
use Test::Exception;
use Test::Warnings;
use Test::MockModule;
use Test::MockObject;
use Test::Mock::Time;
use List::Util qw(any none all);
use testapi qw(set_var);

use sles4sap::crash;

subtest '[crash_deploy_azure]' => sub {
    my $crash = Test::MockModule->new('sles4sap::crash', no_auto => 1);
    $crash->redefine(get_current_job_id => sub { return 'Volta'; });
    my @calls;
    my $azure = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);
    $azure->redefine(assert_script_run => sub { push @calls, $_[0]; return; });

    crash_deploy_azure(region => 'AmanitaMuscaria', os => 'CortinariusCinnabarinus');

    note("\n  -->  " . join("\n  -->  ", @calls));
    ok((any { /az vm create/ } @calls), 'There is one VM create');
};

subtest '[crash_pubip] not supported csp' => sub {
    dies_ok { crash_pubip(provider => 'HelvellaDryophila')};
};

subtest '[crash_pubip]' => sub {
    my $crash = Test::MockModule->new('sles4sap::crash', no_auto => 1);
    $crash->redefine(crash_deploy_name => sub {return 'ImperatorTorosus';});
    my @calls;
    my $azure = Test::MockModule->new('sles4sap::azure_cli', no_auto => 1);
    $azure->redefine(script_output => sub {
        push @calls, $_[0];
        return 'InocybeGeophylla'; });

    my $res = crash_pubip(provider => 'AZURE');

    note("\n  -->  " . join("\n  -->  ", @calls));
    ok(($res eq 'InocybeGeophylla'), "Expected 'InocybeGeophylla' and get $res")
};

subtest '[crash_system_ready]' => sub {
    my $crash = Test::MockModule->new('sles4sap::crash', no_auto => 1);
    my @calls;
    $crash->redefine(script_run => sub {push @calls, $_[0]; return 0; });

    crash_system_ready(ssh_command => 'LactariusTorminosus');

    note("\n  -->  " . join("\n  -->  ", @calls));
    ok((any { /is-system-running/ } @calls), 'There is one VM create');
};

subtest '[crash_softrestart]' => sub {
    my $crash = Test::MockModule->new('sles4sap::crash', no_auto => 1);
    my $mock_pc = Test::MockObject->new();
    $mock_pc->set_true('wait_for_ssh');
    my @calls;
    $mock_pc->mock('ssh_assert_script_run', sub {
            my ($self, %args) = @_;
            push @calls, $args{cmd};
            return; });
    $crash->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });

    crash_softrestart(instance => $mock_pc);

    note("\n  -->  " . join("\n  -->  ", @calls));
    ok((any { /shutdown.*\-r/ } @calls), 'Shutdown command');
};

done_testing;
