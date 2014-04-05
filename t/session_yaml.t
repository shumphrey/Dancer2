#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use open ':utf8';

use YAML::Any;
use Test::More;
use HTTP::Request::Common;
use File::Temp;
use LWP::UserAgent;
use LWP::Protocol::PSGI;

## YAML::Any will normally load in this order
## YAML::XS -> YAML::Syck -> YAML::Old -> YAML -> YAML::Tiny
## Swap the order of these two to make this test fail
@YAML::Any::_TEST_ORDER = ('YAML', 'YAML::XS');

#my @possibles = YAML::Any->order;
my $impl      = YAML::Any->implementation;
note "Using YAML implementation $impl";

my $test_string = '⚒ ⚓ ⚔ ⚕ ⚖ ⚗ ⚘ ⚙';

my $tempdir = File::Temp->newdir();

{
    use Dancer2;
    setting(
        engines => {
            session => { YAML => { session_dir => $tempdir->dirname } }
        }
    );
    setting( session => 'YAML' );
    get '/yaml' => sub {
        session test => $test_string;
        return session->id;
    };

    get '/yaml/read' => sub {
        return session('test');
    };
}

my $app = Dancer2->runner->server->psgi_app;
LWP::Protocol::PSGI->register($app);

my $ua = LWP::UserAgent->new;
my $cookie_jar_dir = File::Temp->newdir;
$ua->cookie_jar({ file => File::Spec->catfile($cookie_jar_dir, '.cookies') });

my $res = $ua->request(GET 'http://local/yaml');

## This test uses the route to set the session then reads the session file
## manually, it should be a utf-8 encoded yaml file.
## The decoded yaml file should contain our test string
## YAML::XS fails this.
is( $res->code, 200, '[/yaml] Correct status' ) or diag $res->status_line;
my $session_id = $res->decoded_content;
my $session_file = File::Spec->catfile($tempdir, $session_id . '.yml');
open my $fh, '<', $session_file;
local undef $/;
my $contents = <$fh>;
like($contents, qr/$test_string/, 'Decoded session file matches test string');

## This test checks that what we read from the session is the same as what
## we put in the session
## Even if something is double encoded into the session file, double decoding
## it ought to reverse the process?
## YAML::XS will fail here also, implying we double encode, but only single
## decode
$res = $ua->request( GET 'http://local/yaml/read' );
is( $res->code, 200, '[/yaml/read] Correct status' );
like( $res->decoded_content, qr/$test_string/, 'reading session matches test_string');


done_testing();

