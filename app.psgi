use strict;
use warnings;
use Twiggy::Server;
use Plack::Request;
use Plack::App::File;

my $server = Twiggy::Server->new(
    port => ($ENV{QS_DATABASE_PORT} or die "QS_DATABASE_PORT env var required"),
);

my $app = sub {
    my $request = Plack::Request->new(shift);
};

use Plack::Builder;
$app = builder {
    mount "/static" => Plack::App::File->new(root => "static/")->to_app;
    mount "/" => $app;
};

$server->register_service($app);

AE::cv->recv;
