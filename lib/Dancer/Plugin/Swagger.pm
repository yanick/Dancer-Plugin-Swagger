# TODO: add responses
# TODO: add examples
# TODO: then add the template for different responses values
# TODO: override send_error ? 
# TODO: add 'validate_schema'
# TODO: add 'strict_schema'
# TODO: make /swagger.json configurable

package Dancer::Plugin::Swagger;
# ABSTRACT: create Swagger documentation of the app REST interface 

use strict;
use warnings;

use Dancer;
use Dancer::Plugin;
use Dancer::Plugin::REST;
use Dancer::Plugin::CORS;
use PerlX::Maybe;

use Dancer::Plugin::Swagger::Path;

use Moo;

with 'MooX::Singleton';
use Class::Load qw/ load_class /;

use Path::Tiny;
use File::ShareDir::Tarball;

sub import {
    $Dancer::Plugin::Swagger::FIRST_LOADED ||= caller;
    goto &Exporter::import;
}

has doc => (
    is => 'ro',
    lazy => 1,
    default => sub { 
        my $self = shift;

        my $doc = {
            swagger => '2.0',
            paths => {},
        };

        $doc->{info}{$_} = '' for qw/ title description version /; 

        $doc->{info}{title} = $self->main_api_module if $self->main_api_module;

        if( my( $desc) = $self->main_api_module_content =~ /
                ^(?:\s* \# \s* ABSTRACT: \s* |=head1 \s+ NAME \s+ (?:\w+) \s+ - \s+  ) ([^\n]+) 
                /xm
        ) {
            $doc->{info}{description} = $desc;
        }

        $doc->{info}{version} = eval {
            $self->main_api_module->VERSION
        } // '0.0.0';

        $doc;
        
    },
);

has main_api_module => (
    is => 'ro',
    lazy => 1,
    default => sub {
        plugin_setting->{main_api_module}
            || $Dancer::Plugin::Swagger::FIRST_LOADED;
    },
);

has main_api_module_content => (
    is => 'ro',
    lazy => 1,
    default => sub { 
        my $mod = $_[0]->main_api_module or return '';
        $mod =~ s#::#/#g;
        $mod .= '.pm';
        Path::Tiny::path( $INC{$mod} )->slurp;
    }
);

has show_ui => (
    is => 'ro',
    lazy => 1,
    default => sub { plugin_setting->{show_ui} // 1 },
);

has ui_url => (
    is => 'ro',
    lazy => 1,
    default => sub { plugin_setting->{ui_url} // '/doc' },
);

has ui_dir => (
    is => 'ro',
    lazy => 1,
    default => sub { 
        Path::Tiny::path(
            plugin_setting->{ui_dir} ||
                File::ShareDir::Tarball::dist_dir('Dancer-Plugin-Swagger')
        )
    },
);

has auto_discover_skip => (
    is => 'ro',
    lazy => 1,
    default => sub { [
            map { /^qr/ ? eval $_ : $_ }
        @{ plugin_setting->{auto_discover_skip} || [
            '/swagger.json', ( 'qr!' . $_[0]->ui_url . '!' ) x $_[0]->show_ui
        ] }
    ];
    },
);

my $plugin = __PACKAGE__->instance;

if ( $plugin->show_ui ) {
    my $base_url = $plugin->ui_url;

    get $base_url => sub {
        my $file = $plugin->ui_dir->child('index.html');

        send_error "file not found", 404 unless -f $file;

        my $content = $file->slurp;
        $content =~ s/UI_DIR/$base_url/g;
        $content =~ s!SWAGGER_URL!uri_for( '/swagger.json'  )!eg;

        $content;
    };

    get $base_url.'/**' => sub {
        my $file = $plugin->ui_dir->child( @{ (splat())[0] } );

        send_error "file not found", 404 unless -f $file;

        send_file $file, system_path => 1;
    };

}

# TODO make the doc url configurable

get '/swagger.json' => sub {
    $plugin->doc
};

register swagger_auto_discover => sub {
    my %args = @_;

    $args{skip} ||= $plugin->auto_discover_skip;

    my $routes = Dancer::App->current->registry->routes;

    my $doc = $plugin->doc->{paths};

    for my $method ( qw/ get post put delete / ) {
        for my $r ( @{ $routes->{$method} } ) {
            my $pattern = $r->pattern;

            next if ref $pattern eq 'Regexp';

            next if grep { ref $_ ? $pattern =~ $_ : $pattern eq $_ } @{ $args{skip} };

            my $path = Dancer::Plugin::Swagger::Path->new( route => $r );

            warn "adding $path";

            $path->add_to_doc($plugin->doc);

        }
    }
};

register swagger_response => sub {
    my %arg = @_;


    Dancer::Plugin::Swagger::Response->new(
        %arg
    );
};


register swagger_path => sub {
    my @routes;
    push @routes, pop @_ while eval { $_[-1]->isa('Dancer::Route') };

    # we don't process HEAD
    @routes = grep { $_->method ne 'head' } @routes;

    my $arg = shift @_ || {}; 

    for my $route ( @routes ) {
        my $path = Dancer::Plugin::Swagger::Path->new(%$arg, route => $route);

        $path->add_to_doc( $plugin->doc );

        my $code = $route->code;
        
        $route->code(sub {
            local $Dancer::Plugin::Swagger::THIS_ACTION = $path;
            $code->();
        });
    }
};

register swagger_template => sub {
    my ( $vars, $status ) = reverse @_;
    $status ||= 'default';
    $vars ||= {};

    return $Dancer::Plugin::Swagger::THIS_ACTION->{hello};
};

register_plugin;

1;
