#!/usr/bin/perl -w

use strict;
use Test::More tests => 7 + 1; # Test::NoWarnings adds one
use Test::NoWarnings;

use Attribute::Storage qw( get_subattr get_subattrs );

sub Title :ATTR(CODE)
{
   my $package = shift;
   my ( $title ) = @_;

   return "" unless defined $title;
   return $title;
}

sub myfunc :Title('The title of myfunc')
{
}

sub emptytitle :Title
{
}

sub anotherfunc
{
}

is( get_subattr( \&myfunc, "Title" ), "The title of myfunc", 'get_subattr Title on \&myfunc' );

is( get_subattr( "myfunc", "Title" ), "The title of myfunc", 'get_subattr Title on "myfunc"' );

is( get_subattr( \&myfunc, "Another" ), undef, 'get_subattr Another' );

is( get_subattr( \&anotherfunc, "Title" ), undef, 'get_subattr Title on \&another' );

is_deeply( get_subattrs( \&myfunc ),
           { Title => "The title of myfunc" },
           'get_subattrs' );

my $coderef;

$coderef = sub :Title('Dynamic code') { 1 };
is( get_subattr( $coderef, "Title" ), "Dynamic code", 'get_subattr Title on anon CODE' );

# We have to put  my $dummy = ...  or else the Perl compiler gets confused.
# Reported to perl-p5p@
$coderef = eval "my \$dummy = sub :Title('eval code') { 2 }" or die $@;
is( get_subattr( $coderef, "Title" ), "eval code", 'get_subattr Title on anon CODE from eval' );
