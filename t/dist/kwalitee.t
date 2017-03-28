#!/usr/bin/perl
use Test::More;
use strict;
use warnings;
BEGIN {
  plan skip_all => 'these tests are for release candidate testing'
    unless $ENV{TEST_AUTHOR};
}

use Test::Kwalitee 'kwalitee_ok';
kwalitee_ok();
done_testing;

