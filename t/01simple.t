#!/usr/bin/perl -w

use strict;
use Test::More tests => 5;

use Attribute::Storage qw( get_subattr get_subattrs );

sub Title : ATTR(CODE)
{
   my $package = shift;
   my ( $title ) = @_;

   return $title;
}

sub myfunc : Title('The title of myfunc')
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
