package Dancer::Plugin::Swagger::Path;

use strict;
use warnings;

use Moo;

use MooseX::MungeHas 'is_ro';

use Carp;
use Hash::Merge;
use List::AllUtils qw/ first /;

has route => ( handles => [ 'pattern' ] );

has method => sub {
    eval { $_[0]->route->method } 
        or croak "no route or explicit method provided to path";
};

has path => sub {
    dancer_pattern_to_swagger_path( $_[0]->route->pattern );
};

has description => ( predicate => 1 );

has parameters => 
    lazy => sub { [] },
    predicate => 1,
;

# TODO allow to pass a hashref instead of an arrayref
sub parameter {
    my( $self, $param, $args ) = @_;

    $args ||= {};
    $args->{name} ||= $param;

    my $p = first { $_->{name} eq $param } @{ $self->parameters };
   
    push @{ $self->parameters }, $p = { name => $param }
        unless $p;

    %$p = %{Hash::Merge::merge( $p, $args )};
}

sub dancer_pattern_to_swagger_path {
    my $pattern = shift;
    $pattern =~ s#(?<=/):(\w+)(?=/|$)#{$1}#g;
    return $pattern;
}

sub add_to_doc {
    my( $self, $doc ) = @_;

    my $path = $self->path;
    my $method = $self->method;

    # already there
    next if $doc->{paths}{$path}{$method};

    my $m = $doc->{paths}{$path}{$method} ||= {};

    $m->{description} = $self->description if $self->has_description;
    $m->{parameters} = $self->parameters if $self->has_parameters;
}

sub BUILD {
    my $self = shift;

    for my $param ( eval { @{ $self->route->{_params} } } ) {
        $self->parameter( $param => {
            in       => 'path',
            required => JSON::true,
            type     => "string",
        } );
    }
}

1;


