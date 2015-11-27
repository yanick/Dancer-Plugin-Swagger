package MyApp;
use Dancer ':syntax';

=head1 NAME

MyApp - Dancing Web Service

=cut

use Dancer::Plugin::Swagger;

our $VERSION = '0.1';

my %judge = (
    'Murphy' => {
        fullname => 'Mary Ann Murphy',
        seasons => [ 3..5, 6, 8..10 ],
    },
);

swagger_path {
    description => 'Returns information about a judge',
    parameters => [
        {
            name => 'judge_name',
            description => 'Last name of the judge',
        },
    ],
},
get '/judge/:judge_name' => sub {
    return $judge{ param('judge_name') };
};

#swagger_auto_discover();

1;
