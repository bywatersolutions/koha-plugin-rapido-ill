#!/usr/bin/perl

use Modern::Perl;

use Test::More tests => 4;
use Test::Exception;

use lib '.';
use Koha::Plugin::Com::ByWaterSolutions::RapidoILL;

my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new;

subtest 'epoch_to_end_of_day basic functionality' => sub {
    plan tests => 4;
    
    # Test with a known epoch timestamp: 2024-09-03 10:30:45 UTC
    my $epoch = 1725360645;
    my $dt = $plugin->epoch_to_end_of_day($epoch);
    
    isa_ok($dt, 'DateTime', 'Returns DateTime object');
    is($dt->year, 2024, 'Correct year');
    is($dt->month, 9, 'Correct month');
    is($dt->day, 3, 'Correct day');
};

subtest 'time normalization to end of day' => sub {
    plan tests => 3;
    
    my $epoch = 1725360645; # 2024-09-03 10:30:45 UTC
    my $dt = $plugin->epoch_to_end_of_day($epoch);
    
    is($dt->hour, 23, 'Hour set to 23');
    is($dt->minute, 59, 'Minute set to 59');
    is($dt->second, 59, 'Second set to 59');
};

subtest 'different epoch values' => sub {
    plan tests => 2;
    
    # Test with different times on same day
    my $morning_epoch = 1725350400; # 2024-09-03 07:40:00 UTC
    my $evening_epoch = 1725390000; # 2024-09-03 18:40:00 UTC
    
    my $dt1 = $plugin->epoch_to_end_of_day($morning_epoch);
    my $dt2 = $plugin->epoch_to_end_of_day($evening_epoch);
    
    is($dt1->hms, '23:59:59', 'Morning epoch normalized to end of day');
    is($dt2->hms, '23:59:59', 'Evening epoch normalized to end of day');
};

subtest 'error handling' => sub {
    plan tests => 1;
    
    throws_ok {
        $plugin->epoch_to_end_of_day();
    } 'RapidoILL::Exception::MissingParameter', 'Throws exception for missing epoch parameter';
};
