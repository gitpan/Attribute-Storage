#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2008,2009 -- leonerd@leonerd.org.uk

package Attribute::Storage;

use strict;
use warnings;
use Carp;

our $VERSION = '0.04';

use base qw( DynaLoader );
__PACKAGE__->DynaLoader::bootstrap( $VERSION );

=head1 NAME

C<Attribute::Storage> - declare and retrieve named attributes about CODE
references

=head1 SYNOPSIS

 package My::Package;

 use Attribute::Storage;

 sub Title : ATTR(CODE)
 {
    my $package = shift;
    my ( $title ) = @_;

    return $title;
 }

 1;

 package main

 use Attribute::Storage qw( get_subattr );
 use My::Package;

 sub myfunc : Title('The title of my function')
 {
    ...
 }

 print "Title of myfunc is: ".get_subattr(\&myfunc, 'Title')."\n";

=head1 DESCRIPTION

This package provides a base, where a package using it can define handlers for
particular code attributes. Other packages, using the package that defines the
code attributes, can then use them to annotate subs.

This is similar to C<Attribute::Handlers>, with the following key differences:

=over 4

=item *

C<Attribute::Storage> will store the value returned by the attribute handling
code, and provides convenient lookup functions to retrieve it later.
C<Attribute::Handlers> simply invokes the handling code.

=item *

C<Attribute::Storage> immediately executes the attribute handling code at
compile-time.  C<Attribute::Handlers> defers invocation so it can look up the
symbolic name of the sub the attribute is attached to. An upshot here is that
the invoked code in C<Attribute::Storage> does not know the name of the sub it
attaches to.

=item *

C<Attribute::Storage> is safe to use on code that will be reloaded, because it
executes handlers immediately. C<Attribute::Handlers> will only execute
handlers at defined phases such as C<BEGIN> or C<INIT>, and cannot reexecute
the handlers in a file once it has been reloaded.

=back

=cut

sub import
{
   my $class = shift;
   return unless $class eq __PACKAGE__;

   my $caller = caller;

   my $sub = sub {
      my ( $pkg, $ref, @attrs ) = @_;
      return @attrs unless ref $ref eq "CODE";
      grep { handle_attr( $pkg, $ref, $_ ) } @attrs;
   };

   no strict 'refs';
   *{$caller . "::MODIFY_CODE_ATTRIBUTES"} = $sub;

   # Some simple Exporter-like logic. Just does function refs
   foreach my $symb ( @_ ) {
      $sub = __PACKAGE__->can( $symb ) or croak __PACKAGE__." has no function '$symb'";
      *{$caller . "::$symb"} = $sub;
   }
}

=head1 ATTRIBUTES

Each attribute that the defining package wants to define should be done using
a marked subroutine, in a way similar to L<Attribute::Handlers>. When a sub in
the using package is marked with such an attribute, the code is executed,
passing in the arguments. Whatever it returns is stored, to be returned later
when queried by C<get_subattr> or C<get_subattrs>. The return value must be
defined, or else the attribute will be marked as a compile error for perl to
handle accordingly.

Only C<CODE> attributes are supported at present.

 sub AttributeName : ATTR(CODE)
 {
    my $package = shift;
    my ( $attr, $args, $here ) = @_;
    ...
    return $value;
 }

At attachment time, the optional string that may appear within brackets
following the attribute's name is parsed as a Perl expression in list context.
If this succeeds, the values are passed as a list to the handling code. If
this fails, an error is returned to the perl compiler. If no string is
present, then an empty list is passed to the handling code.

 package Defining;

 sub NameMap : ATTR(CODE)
 {
    my $package = shift;
    my @strings = @_;

    return { map { m/^(.*)=(.*)$/ and ( $1, $2 ) } @strings };
 }

 package Using;

 use Defining;

 sub somefunc : NameMap("foo=FOO","bar=BAR","splot=WIBBLE") { ... }

 my $map = get_subattr("somefunc", "NameMap");
 # Will yield:
 #  { foo   => "FOO",
 #    bar   => "BAR",
 #    splot => "WIBBLE" }

Note that it is impossible to distinguish

 sub somefunc : NameMap   { ... }
 sub somefunc : NameMap() { ... }

It is possible to create attributes that do not parse their argument as a perl
list expression, instead they just pass the plain string as a single argument.
For this, add the C<RAWDATA> flag to the C<ATTR()> list.

 sub Title : ATTR(CODE,RAWDATA)
 {
    my $package = shift;
    my ( $text ) = @_;

    return $text;
 }

 sub thingy : Title(Here is the title for thingy) { ... }

=cut

sub handle_attr
{
   my ( $package, $ref, $attr ) = @_;

   my ( $attrname, $opts ) = $attr =~ m/^([a-zA-Z_]+)(\(.*\))?$/s or return 1;

   if( defined $opts ) {
      s/^\(//, s/\)$// for $opts; # trim wrapping ()
   }

   my $cv;
   my $type;
   if( $attrname eq "ATTR" ) {
      $type = { raw => 1 };
   }
   else {
      $cv = $package->can( $attrname ) or return 1;
      my $attrs = _get_attr_hash( $cv, 0 ) or return 1;
      $type = $attrs->{ATTR} or return 1;
   }

   my @opts;
   if( $type->{raw} ) {
      @opts = ( $opts );
   }
   else {
      @opts = do {
         no strict;
         defined $opts ? eval $opts : ();
      };

      if( $@ ) {
         my ( $msg ) = $@ =~ m/^(.*) at \(eval \d+\) line \d+\.$/;
         croak "Unable to parse $attrname - $msg";
      }
   }

   if( $attrname eq "ATTR" ) {
      my %type;
      foreach ( split m/\s*,\s*/, $opts[0] ) {
         m/^CODE$/ and next;

         m/^SCALAR|HASH|ARRAY$/ and 
            croak "Only CODE attributes are supported currently";

         m/^RAWDATA$/ and
            ( $type{raw} = 1 ), next;

         croak "Unrecognised attribute option $_";
      }

      _get_attr_hash( $ref, 1 )->{ATTR} = \%type;
   }
   else {
      my $value = eval { $cv->( $package, @opts ) };
      die $@ if $@;
      defined $value or return 1;

      _get_attr_hash( $ref, 1 )->{$attrname} = $value;
   }

   return 0;
}

=head1 FUNCTIONS

=cut

=head2 $attrs = get_subattrs( $sub )

Returns a HASH reference containing all the attributes defined on the given
sub. The sub should either be passed as a CODE reference, or as a name in the
caller's package. If no attributes are defined, a reference to an empty HASH
is returned.

The returned HASH reference is a new shallow clone, the caller may modify this
hash arbitrarily without breaking the stored data, or other users of it.

=cut

sub get_subattrs
{
   my ( $sub ) = @_;

   defined $sub or croak "Need a sub";

   my $cv;
   if( ref $sub ) {
      $cv = $sub;
   }
   else {
      my $caller = caller;
      $cv = $caller->can( $sub );
      defined $cv or croak "$caller has no sub $sub";
   }

   return { %{ _get_attr_hash( $cv, 0 ) || {} } }; # clone
}

=head2 $value = get_subattr( $sub, $attrname )

Returns the value of a single named attribute on the given sub. The sub should
either be passed as a CODE reference, or as a name in the caller's package. If
the attribute is not defined, C<undef> is returned.

=cut

sub get_subattr
{
   my ( $sub, $attr ) = @_;

   defined $sub or croak "Need a sub";

   my $cv;
   if( ref $sub ) {
      $cv = $sub;
   }
   else {
      my $caller = caller;
      $cv = $caller->can( $sub );
      defined $cv or croak "$caller has no sub $sub";
   }

   my $attrhash = _get_attr_hash( $cv, 0 ) or return undef;
   return $attrhash->{$attr};
}

# Keep perl happy; keep Britain tidy
1;

__END__

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>
