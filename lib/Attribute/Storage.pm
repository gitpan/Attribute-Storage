#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2008-2012 -- leonerd@leonerd.org.uk

package Attribute::Storage;

use strict;
use warnings;

use Carp;

our $VERSION = '0.08';

require XSLoader;
XSLoader::load( __PACKAGE__, $VERSION );

use B qw( svref_2object );

=head1 NAME

C<Attribute::Storage> - declare and retrieve named attributes about CODE
references

=head1 SYNOPSIS

 package My::Package;

 use Attribute::Storage;

 sub Title :ATTR(CODE)
 {
    my $package = shift;
    my ( $title ) = @_;

    return $title;
 }

 package main;

 use Attribute::Storage qw( get_subattr );
 use My::Package;

 sub myfunc :Title('The title of my function')
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
compile-time. C<Attribute::Handlers> defers invocation so it can look up the
symbolic name of the sub the attribute is attached to. C<Attribute::Storage>
uses L<B> to provide the name of the sub at invocation time, using the name of
the underlying C<GV>.

=item * 

C<Attribute::Storage> works just as well on anonymous subs as named ones.

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

   # TODO
   #Attribute::Lexical->import( 'CODE:ATTR' => \&handle_attr_ATTR );

   my $caller = caller;

   my $sub = sub {
      my ( $pkg, $ref, @attrs ) = @_;
      grep {
         my ( $attrname, $opts ) = m/^([A-Za-z_][0-9A-Za-z_]*)(?:\((.*)\))?$/s;
         defined $opts or $opts = "";
         $attrname eq "ATTR" ?
            handle_attr_ATTR( $pkg, $ref, $attrname, $opts ) :
            handle_attr     ( $pkg, $ref, $attrname, $opts );
      } @attrs;
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

 sub AttributeName :ATTR(CODE)
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

 sub NameMap :ATTR(CODE)
 {
    my $package = shift;
    my @strings = @_;

    return { map { m/^(.*)=(.*)$/ and ( $1, $2 ) } @strings };
 }

 package Using;

 use Defining;

 sub somefunc :NameMap("foo=FOO","bar=BAR","splot=WIBBLE") { ... }

 my $map = get_subattr("somefunc", "NameMap");
 # Will yield:
 #  { foo   => "FOO",
 #    bar   => "BAR",
 #    splot => "WIBBLE" }

Note that it is impossible to distinguish

 sub somefunc :NameMap   { ... }
 sub somefunc :NameMap() { ... }

It is possible to create attributes that do not parse their argument as a perl
list expression, instead they just pass the plain string as a single argument.
For this, add the C<RAWDATA> flag to the C<ATTR()> list.

 sub Title :ATTR(CODE,RAWDATA)
 {
    my $package = shift;
    my ( $text ) = @_;

    return $text;
 }

 sub thingy :Title(Here is the title for thingy) { ... }

To obtain the name of the function to which the attribute is being applied,
use the C<NAME> flag to the C<ATTR()> list.

 sub Callable :ATTR(CODE,NAME)
 {
    my $package = shift;
    my ( $subname, @args ) = @_;

    print "The Callable attribute is being applied to $package :: $subname\n";

    return;
 }

When applied to an anonymous function (C<sub { ... }>), the name will appear
as C<__ANON__>.

Normally it is an error to attempt to apply the same attribute more than once
to the same function. Sometimes however, it would make sense for an attribute
to be applied many times. If the C<ATTR()> list is given the C<MULTI> flag,
then applying it more than once will be allowed. Each invocation of the
handling code will be given the previous value that was returned, or C<undef>
for the first time. It is up to the code to perform whatever merging logic is
required.

 sub Description :ATTR(CODE,MULTI,RAWDATA)
 {
    my $package = shift;
    my ( $olddesc, $more ) = @_;

    return defined $olddesc ? "$olddesc$more\n" : "$more\n";
 }

 sub Argument :ATTR(CODE,MULTI)
 {
    my $package = shift;
    my ( $args, $argname ) = @_;

    push @$args, $argname;
    return $args;
 }

 sub Option :ATTR(CODE,MULTI)
 {
    my $package = shift;
    my ( $opts, $optname ) = @_;

    $opts and exists $opts->{$optname} and
       croak "Already have the $optname option";

    $opts->{$optname}++;
    return $opts;
 }

 ...

 sub do_copy
    :Description(Copy from SOURCE to DESTINATION)
    :Description(Optionally preserves attributes)
    :Argument("SOURCE")
    :Argument("DESTINATION")
    :Option("attrs")
    :Option("verbose")
 {
    ...
 }

=cut

sub handle_attr_ATTR
{
   my ( $pkg, $ref, undef, $opts ) = @_;

   my $attrs = _get_attr_hash( $ref, 1 );

   my %type;
   foreach ( split m/\s*,\s*/, $opts ) {
      m/^CODE$/ and next;

      m/^SCALAR|HASH|ARRAY$/ and 
         croak "Only CODE attributes are supported currently";

      m/^RAWDATA$/ and
         ( $type{raw} = 1 ), next;

      m/^MULTI$/ and
         ( $type{multi} = 1 ), next;

      m/^NAME$/ and
         ( $type{name} = 1 ), next;

      croak "Unrecognised attribute option $_";
   }

   $attrs->{ATTR} = \%type;

   return 0;
}

sub handle_attr
{
   my ( $pkg, $ref, $attrname, $opts ) = @_;

   my $cv = $pkg->can( $attrname ) or return 1;
   my $cvattrs = _get_attr_hash( $cv, 0 ) or return 1;
   my $type = $cvattrs->{ATTR} or return 1;

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

   my $attrs = _get_attr_hash( $ref, 1 );

   if( $type->{name} ) {
      unshift @opts, svref_2object( $ref )->GV->NAME;
   }

   if( $type->{multi} ) {
      unshift @opts, $attrs->{$attrname};
   }
   else {
      exists $attrs->{$attrname} and 
         croak "Already have the $attrname attribute";
   }

   my $value = eval { $cv->( $pkg, @opts ) };
   die $@ if $@;
   defined $value or return 1;

   $attrs->{$attrname} = $value;

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

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
