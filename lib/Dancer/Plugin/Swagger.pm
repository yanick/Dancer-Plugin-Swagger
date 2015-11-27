# TODO: make /swagger.json configurable

package Dancer::Plugin::Swagger;
# ABSTRACT: create Swagger documentation of the app REST interface 

=head1 SYNOPSIS

    package MyApp;

    use Dancer;
    use Dancer::Plugin::Swagger;

    our $VERSION = "0.1";

    get '/choreograph/:name' => sub { ... };

    1;


=head1 DESCRIPTION

This plugin provides tools to create and access a L<http://swagger.io/|Swagger> specification file for a
Dancer REST web service.

Overview of C<Dancer::Plugin::Swagger>'s features:

=over

=item Can create a f</swagger.json> REST specification file.

=item Can auto-discover routes and add them to the swagger file.

=item Can provide a Swagger UI version of the swagger documentation.

=back


=head1 CONFIGURATION

    plugins:
        Swagger:
           main_api_module: MyApp
           show_ui: 1
           ui_url: /doc
           ui_dir: /path/to/files
           auto_discover_skip:
            - /swagger.json
            - qr#^/doc/#

=head2 main_api_module

If not provided explicitly, the Swagger document's title and version will be set
to the abstract and version of this module. 

Defaults to the first
module to import L<Dancer::Plugin::Swagger>.

=head2 show_ui

If C<true>, a route will be created for the Swagger UI (see L<http://swagger.io/swagger-ui/>).

Defaults to C<true>.

=head2 ui_url

Path of the swagger ui route. Will also be the prefix for all the CSS/JS dependencies of the page.

Defaults to C</doc>.

=head2 ui_dir

Filesystem path to the directory holding the assets for the Swagger UI page.

Defaults to a copy of the Swagger UI code bundled with the L<Dancer::Plugin::Swagger> distribution.

=head2 auto_discover_skip

List of urls that should not be added to the Swagger document by C<swagger_auto_discover>.
If an url begins with C<qr>, it will be compiled as a regular expression.

Defauls to C</swagger.json> and, if C<show_ui> is C<true>, all the urls under C<ui_url>.

=head1 EXAMPLES

See the F<examples/> directory of the distribution for a working example.

=head1 SEE ALSO

=over

=item L<http://swagger.io/|Swagger>

=back

=cut

use strict;
use warnings;

use Dancer;
use Dancer::Plugin;
use Dancer::Plugin::REST;
use Dancer::Plugin::CORS;
use PerlX::Maybe;

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

=head1 EXPORTED KEYWORDS

=head2 swagger_auto_discover skip => \@list

Populates the Swagger document with information of all
the routes of the application.

Accepts an optional C<skip> parameter that takes an arrayref of
routes that shouldn't be added to the Swagger document. The routes
can be specified as-is, or via regular expressions. If no skip list is given, defaults to 
the c<auto_discover_skip> configuration value.

    swagger_auto_discover skip => [ '/swagger.json', qr#^/doc/# ];

The information of a route won't be altered if it's 
already present in the document.

If a route has path parameters, they will be automatically
added as such in the C<parameters> section.

Routes defined as regexes are skipped, as there is no clean way
to automatically make them look nice.

        # will be picked up
    get '/user' => ...;

        # ditto, as '/user/{user_id}'
    get '/user/:user_id => ...;

        # won't be picked up
    get qr#/user/(\d+)# => ...;


Note that routes defined after C<swagger_auto_discover> has been called won't 
be added to the Swagger document. Typically, you'll want C<swagger_auto_discover>
to be called at the very end of your module. Alternatively, C<swagger_auto_discover>
can be called more than once safely -- which can be useful if an application creates
routes dynamically.

=cut

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

            $pattern =~ s#(?<=/):(\w+)(?=/|$)#{$1}#g;

            # already there
            next if $doc->{$pattern}{$method};

            my $method = $doc->{$pattern}{$method} = {};

            for my $param ( @{ $r->{_params} || [] } ) {
                push @{ $method->{parameters} }, {
                    name     => $param,
                    in       => 'path',
                    required => JSON::true,
                    type     => "string",
                };
            }
        }
    }
};

register swagger_response => sub {
    my %arg = @_;


    Dancer::Plugin::Swagger::Response->new(
        %arg
    );
};

register swagger_action => sub {
    my( $arg, @routes ) = @_;

    for ( @routes ) {
        next unless $_->method eq 'get';
        my $code = $_->code;
        $_->code(sub {
            local $Dancer::Plugin::Swagger::THIS_ACTION = $arg;
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
