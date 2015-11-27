package MyApp;
use Dancer ':syntax';

=head1 NAME

MyApp - Dancing Web Service

=cut

use Dancer::Plugin::Swagger;

our $VERSION = '0.1';

get '/' => sub {
    'hello';
};

get '/choreograph/:name' => sub {
    ...;
};

swagger_auto_discover();

1;
