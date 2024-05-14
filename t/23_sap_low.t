use strict;
use warnings;
use Test::More;
use Test::Exception;
use Test::MockModule;

use sles4sap::sap_some_low;

subtest '[low_greeting]' => sub {
    my $ret = low_greeting(name => 'Michele');

    like($ret, qr/ELEHCIM/, "Greeting has the proper format");
};


subtest '[low_greeting] die at missing argument' => sub {
    dies_ok { low_greeting() } 'Die for missing argument name';
};

subtest '[low_init]' => sub {
    my $ssl = Test::MockModule->new('sles4sap::sap_some_low', no_auto => 1);

    my @calls;
    $ssl->redefine(assert_script_run => sub { push @calls, $_[0]; return; });

    low_init(
        group => 'openqa-rg',
        region => 'westeurope',
        vnet => 'openqa-vnet',
        snet => 'openqa-subnet');

    note("\n  -->  " . join("\n  -->  ", @calls));
    ok 1;
};

done_testing;
