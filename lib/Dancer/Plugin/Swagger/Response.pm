package Dancer::Plugin::Swagger::Response;

use Dancer;

use Moo;

extends 'Dancer::Response';

use overload '&{}' => \&gen_from_example,
                '""' => sub { (shift)->{status} };

has desc    => ( is => 'ro' );
has example => ( is => 'ro' );

sub fill_example {
    my($var,$struct) = @_;

    if( ref $struct eq 'ARRAY' ) {
        return [ map { fill_example( $var, $_ ) } @$struct ]
    }

    if( ref $struct eq 'HASH' ) {
        return { map { fill_example( $var, $_ ) } %$struct }
    }

    if( $struct =~ /^\$\{(\w+):.*\}$/ ) {
        die "missing variable '$1'" unless exists $var->{$1};
        return $var->{$1};
    }

    return $struct;
}

sub gen_from_example {
    my $self = shift;
    sub {
        my %var = @_;

        my $content = fill_example( \%var, $self->example );

        status( $self->status // 200 );
        $content;
    }
}

1;
