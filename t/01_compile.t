#!/usr/bin/perl

# Load test the Test::File::Cleaner module

use strict;
BEGIN {
	$|  = 1;
	$^W = 1;
}


# Does everything load?
use Test::More 'tests' => 2;

ok( $] >= 5.005, 'Your perl is new enough' );

use_ok( 'Test::File::Cleaner' );
