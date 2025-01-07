use strict;
use warnings;
use Test::More;
use Test::Exception;
use Test::Warnings;
use Test::MockModule;
use Data::Dumper;
use List::Util qw(any);
use testapi;
use saputils;


subtest '[calculate_hana_topology] invalid output' => sub {
    my $saputils = Test::MockModule->new('saputils', no_auto => 1);
    $saputils->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });
    my $topology = calculate_hana_topology(input => 'PUFFI');
    ok keys %$topology == 0, 'No entry in topology if SAPHanaSR-showAttr has nothing';
};

subtest '[calculate_hana_topology] minimal 2 nodes' => sub {
    my $saputils = Test::MockModule->new('saputils', no_auto => 1);
    $saputils->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });
    my $topology = calculate_hana_topology(input => 'Global/global/cib-time="Thu Feb  1 18:33:56 2024"
Global/global/maintenance="false"
Sites/site_b/b="SOK"
Hosts/vmhana01/vhost="AAAAAAA"
Hosts/vmhana02/vhost="BBBBBBB"');
    ok keys %$topology == 2, 'Output is about exactly 2 hosts';
    ok((any { qr/vmhana01/ } keys %$topology), 'External hash has key vmhana01');
    ok((any { qr/vmhana02/ } keys %$topology), 'External hash has key vmhana02');
};

subtest '[calculate_hana_topology] minimal 2 nodes angi' => sub {
    my $saputils = Test::MockModule->new('saputils', no_auto => 1);
    $saputils->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });
    my $topology = calculate_hana_topology(input => '0 Global/global/sid="HA0"
0 Host/vmhana01/vhost="AAAAAAAA"
0 Host/vmhana01/vhost="BBBBBBBB"');
    ok keys %$topology == 2, 'Output is about exactly 2 hosts';
    ok((any { qr/vmhana01/ } keys %$topology), 'External hash has key vmhana01');
    ok((any { qr/vmhana02/ } keys %$topology), 'External hash has key vmhana02');
};

subtest '[calculate_hana_topology] internal keys' => sub {
    my $saputils = Test::MockModule->new('saputils', no_auto => 1);
    $saputils->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });

    my $topology = calculate_hana_topology(input => 'Global/global/cib-time="Thu Feb  1 18:33:56 2024"
Global/global/maintenance="false"
Sites/site_b/b="SOK"
Hosts/vmhana01/remoteHost="vmhana02"
Hosts/vmhana01/sync_state="PRIM"
Hosts/vmhana01/vhost="vmhana01"
Hosts/vmhana02/remoteHost="vmhana01"
Hosts/vmhana02/sync_state="SOK"
Hosts/vmhana02/vhost="vmhana02"');

    note("Parsed input looks like " . Dumper($topology));
    ok((keys %$topology eq 2), "Parsed input has two hosts, so two outer keys.");

    while (my ($key, $value) = each %$topology) {
        ok((keys %$value eq 3), "Parsed input has 3 values for each host, so 3 inner keys.");

        # how to access one value of an inner hash
        like(%$value{remoteHost}, qr/vmhana0/, 'remoteHost is like vmhana0');
    }
    # how to access one inner value in one shot
    ok((%$topology{vmhana01}->{sync_state} eq 'PRIM'), 'sync_state of vmhana01 is exactly PRIM');
};

subtest '[check_hana_topology] healthy cluster' => sub {
    my $saputils = Test::MockModule->new('saputils', no_auto => 1);
    $saputils->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });

    my $topology = calculate_hana_topology(input => 'Global/global/cib-time="Thu Feb  1 18:33:56 2024"
Global/global/maintenance="false"
Sites/site_b/b="SOK"
Hosts/vmhana01/remoteHost="vmhana02"
Hosts/vmhana01/node_state="online"
Hosts/vmhana01/sync_state="PRIM"
Hosts/vmhana01/vhost="vmhana01"
Hosts/vmhana02/remoteHost="vmhana01"
Hosts/vmhana02/node_state="online"
Hosts/vmhana02/sync_state="SOK"
Hosts/vmhana02/vhost="vmhana02"');

    my $topology_ready = check_hana_topology(input => $topology);

    ok(($topology_ready == 1), 'healthy cluster leads to the return of 1');
};

subtest '[check_hana_topology] healthy angi cluster' => sub {
    my $saputils = Test::MockModule->new('saputils', no_auto => 1);
    $saputils->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });

    my $topology = calculate_hana_topology(input => '0 Global/global/sid="HA0"
0 Global/global/sec="site_b"
0 Global/global/topology="ScaleUp"
0 Global/global/prim="site_a"
0 Global/global/cib-update="0.82.0"
0 Global/global/dcid="1"
0 Resource/mst_SAPHanaCtl_HA0_HDB00/maintenance="false"
0 Host/vmhana01/vhost="vmhana01"
0 Host/vmhana01/site="site_a"
0 Host/vmhana01/version="2.00.077.00"
0 Host/vmhana01/srah="-"
0 Host/vmhana01/clone_state="PROMOTED"
0 Host/vmhana01/score="150"
0 Host/vmhana01/roles="master1:master:worker:master"
0 Host/vmhana02/vhost="vmhana02"
0 Host/vmhana02/site="site_b"
0 Host/vmhana02/version="2.00.077.00"
0 Host/vmhana02/srah="-"
0 Host/vmhana02/clone_state="DEMOTED"
0 Host/vmhana02/score="100"
0 Host/vmhana02/roles="master1:master:worker:master"');

    my $topology_ready = check_hana_topology(input => $topology);

    ok(($topology_ready == 1), 'healthy cluster leads to the return of 1');
};

subtest '[check_hana_topology] healthy cluster with custom node_state_match' => sub {
    my $saputils = Test::MockModule->new('saputils', no_auto => 1);
    $saputils->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });

    my $topology = calculate_hana_topology(input => 'Global/global/cib-time="Thu Feb  1 18:33:56 2024"
Global/global/maintenance="false"
Sites/site_b/b="SOK"
Hosts/vmhana01/remoteHost="vmhana02"
Hosts/vmhana01/node_state="PAPERINO"
Hosts/vmhana01/sync_state="PRIM"
Hosts/vmhana01/vhost="vmhana01"
Hosts/vmhana02/remoteHost="vmhana01"
Hosts/vmhana02/node_state="PAPERINO"
Hosts/vmhana02/sync_state="SOK"
Hosts/vmhana02/vhost="vmhana02"');

    my $topology_ready = check_hana_topology(input => $topology, node_state_match => 'PAPERINO');

    ok(($topology_ready == 1), 'healthy cluster leads to the return of 1');
};

subtest '[check_hana_topology] healthy cluster with custom node_state_match pacemaker 2.1.7' => sub {
    my $saputils = Test::MockModule->new('saputils', no_auto => 1);
    $saputils->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });

    my $topology = calculate_hana_topology(input => 'Global/global/cib-time="Thu Feb  1 18:33:56 2024"
Global/global/maintenance="false"
Sites/site_b/b="SOK"
Hosts/vmhana01/remoteHost="vmhana02"
Hosts/vmhana01/node_state="1234"
Hosts/vmhana01/sync_state="PRIM"
Hosts/vmhana01/vhost="vmhana01"
Hosts/vmhana02/remoteHost="vmhana01"
Hosts/vmhana02/node_state="5678"
Hosts/vmhana02/sync_state="SOK"
Hosts/vmhana02/vhost="vmhana02"');

    my $topology_ready = check_hana_topology(input => $topology, node_state_match => '\d');

    ok(($topology_ready == 1), 'healthy cluster leads to the return of 1');
};

subtest '[check_hana_topology] healthy cluster with custom node_state_match pacemaker 2.1.7' => sub {
    my $saputils = Test::MockModule->new('saputils', no_auto => 1);
    $saputils->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });

    my $topology = calculate_hana_topology(input => 'Global/global/cib-time="Thu Feb  1 18:33:56 2024"
Global/global/maintenance="false"
Sites/site_b/b="SOK"
Hosts/vmhana01/remoteHost="vmhana02"
Hosts/vmhana01/node_state="1234"
Hosts/vmhana01/sync_state="PRIM"
Hosts/vmhana01/vhost="vmhana01"
Hosts/vmhana02/remoteHost="vmhana01"
Hosts/vmhana02/node_state="0"
Hosts/vmhana02/sync_state="SOK"
Hosts/vmhana02/vhost="vmhana02"');

    my $topology_ready = check_hana_topology(input => $topology, node_state_match => '[1-9]');

    ok(($topology_ready == 0), 'unhealthy cluster leads to the return of 0');
};

subtest '[check_hana_topology] unhealthy cluster not online' => sub {
    my $saputils = Test::MockModule->new('saputils', no_auto => 1);
    $saputils->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });

    my $topology = calculate_hana_topology(input => 'Global/global/cib-time="Thu Feb  1 18:33:56 2024"
Global/global/maintenance="false"
Sites/site_b/b="SOK"
Hosts/vmhana01/remoteHost="vmhana02"
Hosts/vmhana01/node_state="NOT ONLINE AT ALL"
Hosts/vmhana01/sync_state="PRIM"
Hosts/vmhana01/vhost="vmhana01"
Hosts/vmhana02/remoteHost="vmhana01"
Hosts/vmhana02/node_state="online"
Hosts/vmhana02/sync_state="SOK"
Hosts/vmhana02/vhost="vmhana02"');

    my $topology_ready = check_hana_topology(input => $topology);

    ok(($topology_ready == 0), 'unhealthy cluster leads to the return of 0');
};

subtest '[check_hana_topology] unhealthy cluster no PRIM' => sub {
    my $saputils = Test::MockModule->new('saputils', no_auto => 1);
    $saputils->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });

    my $topology = calculate_hana_topology(input => 'Global/global/cib-time="Thu Feb  1 18:33:56 2024"
Global/global/maintenance="false"
Sites/site_b/b="SOK"
Hosts/vmhana01/remoteHost="vmhana02"
Hosts/vmhana01/node_state="online"
Hosts/vmhana01/sync_state="SOK"
Hosts/vmhana01/vhost="vmhana01"
Hosts/vmhana02/remoteHost="vmhana01"
Hosts/vmhana02/node_state="online"
Hosts/vmhana02/sync_state="SOK"
Hosts/vmhana02/vhost="vmhana02"');

    my $topology_ready = check_hana_topology(input => $topology);

    ok(($topology_ready == 0), 'unhealthy cluster leads to the return of 0');
};


subtest '[check_hana_topology] unhealthy cluster SFAIL' => sub {
    my $saputils = Test::MockModule->new('saputils', no_auto => 1);
    $saputils->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });

    my $topology = calculate_hana_topology(input => 'Global/global/cib-time="Thu Feb  1 18:33:56 2024"
Global/global/maintenance="false"
Sites/site_b/b="SOK"
Hosts/vmhana01/remoteHost="vmhana02"
Hosts/vmhana01/node_state="online"
Hosts/vmhana01/sync_state="PRIM"
Hosts/vmhana01/vhost="vmhana01"
Hosts/vmhana02/remoteHost="vmhana01"
Hosts/vmhana02/node_state="online"
Hosts/vmhana02/sync_state="SFAIL"
Hosts/vmhana02/vhost="vmhana02"');

    my $topology_ready = check_hana_topology(input => $topology);

    ok(($topology_ready == 0), 'unhealthy cluster leads to the return of 0');
};

subtest '[check_hana_topology] unhealthy cluster missing field' => sub {
    my $saputils = Test::MockModule->new('saputils', no_auto => 1);
    $saputils->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });

    my $topology = calculate_hana_topology(input => 'Global/global/cib-time="Thu Feb  1 18:33:56 2024"
Global/global/maintenance="false"
Sites/site_b/b="SOK"
Hosts/vmhana01/remoteHost="vmhana02"
Hosts/vmhana01/node_state="online"
Hosts/vmhana01/sync_state="PRIM"
Hosts/vmhana01/vhost="vmhana01"
Hosts/vmhana02/remoteHost="vmhana01"
Hosts/vmhana02/node_state="online"
Hosts/vmhana02/vhost="vmhana02"');

    my $topology_ready = check_hana_topology(input => $topology);

    ok(($topology_ready == 0), 'unhealthy cluster leads to the return of 0');
};

subtest '[check_hana_topology] invalid input' => sub {
    my $saputils = Test::MockModule->new('saputils', no_auto => 1);
    $saputils->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });

    my $topology = calculate_hana_topology(input => 'Balamb Garden');

    my $topology_ready = check_hana_topology(input => $topology);

    ok(($topology_ready == 0), 'invalid input leads to the return of 0');
};

subtest '[check_crm_output] input argument is mandatory' => sub {
    dies_ok { check_crm_output() };
};

subtest '[check_crm_output] no starting no failed' => sub {
    my $saputils = Test::MockModule->new('saputils', no_auto => 1);
    $saputils->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });
    my $ret = check_crm_output(input => 'PUFFI');
    ok $ret eq 1, "Ret:$ret has to be 1";
};

subtest '[check_crm_output] starting and failed' => sub {
    my $saputils = Test::MockModule->new('saputils', no_auto => 1);
    $saputils->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', @_)); });
    my $ret = check_crm_output(input => '
        :  Starting
        Failed Resource Actions:');
    ok $ret eq 0, "Ret:$ret has to be 0";
};

done_testing;
