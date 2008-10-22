#!/usr/bin/perl -w

use strict;
use Test::More tests => 1;

use Attribute::Storage qw( get_subattr );

sub Number : ATTR(CODE)
{
   my $package = shift;
   my ( @values ) = @_;

   my $total;
   $total += $_ for @values;

   return $total;
}

sub myfunc : Number(1,2,3,4,5)
{
}

is( get_subattr( \&myfunc, "Number" ), 15, 'get_subattr Number on \&myfunc' );
