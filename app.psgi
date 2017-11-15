use strict;
use warnings;
use Twiggy::Server;
use Plack::Request;
use Plack::App::File;
use JSON 'to_json';
use List::Util 'uniq';
use QS::Database;
use Encode 'encode_utf8';
use WWW::Form::UrlEncoded qw/build_urlencoded/;

my $server = Twiggy::Server->new(
    port => ($ENV{QS_DATABASE_PORT} or die "QS_DATABASE_PORT env var required"),
);

my $database = QS::Database->new(
    file => ($ENV{QS_DATABASE_FILE} or die "QS_DATABASE_FILE env var required"),
);

my %Subscribers;

sub notify_event {
    my $event = shift;
    my $json = encode_utf8(to_json($event)) . "\n";
    my @types = (0, $event->{type});
    for my $type (@types) {
        my @ok_subscribers;
        for (@{ $Subscribers{$type} }) {
            eval { $_->write($json) };
            if (!$@) {
                push @ok_subscribers, $_;
            }
        }

        @{ $Subscribers{$type} } = @ok_subscribers;
    }
}

use Plack::Builder;
my $app = builder {
    enable "ReverseProxyPath";

    enable "+QS::Middleware::Auth", database => $database;

    enable "Deflater",
        content_type => ['text/css','text/html','text/javascript','application/javascript','application/json'];

    mount "/static" => Plack::App::File->new(root => "static/")->to_app;

    mount "/add" => sub {
        my $request = Plack::Request->new(shift);
        my %args;

        my @required_fields = qw/timestamp type isDiscrete/;
        my @optional_fields = qw/uri metadata isStart otherEndpoint duration/;

        for my $key (@required_fields) {
            if (!defined($request->param($key))) {
                return [400, ['Content-Type', 'text/plain'], ["Field '$key' required"]];
            }
        }

        for my $key (@required_fields, @optional_fields) {
            $args{$key} = $request->param($key);
        }

        my $id = $database->insert(%args);
        if ($id) {
            my ($event) = $database->events(id => $id);
            notify_event($event);
            return [201, ['Content-Type', 'application/json'], [
                encode_utf8(to_json($event)),
            ]];
        }
        else {
            return [400, ['Content-Type', 'text/plain'], ['Bad Request']];
        }
    };

    mount "/types" => sub {
        return [200, ['Content-Type', 'application/json'], [
            encode_utf8(to_json($database->event_types)),
        ]];
    };

    mount "/events" => sub {
        my $req = Plack::Request->new(shift);
        my @results = $database->events(
            type => scalar($req->param('type')),
            before => scalar($req->param('before')),
            fields => [$req->parameters->get_all('fields')],
        );

        my %response = (
            results => \@results,
        );

        if (@results) {
            my $next = $req->uri;
            $next->scheme('https');

            my $params = $req->parameters->clone;
            $params->set(before => $results[-1]->{timestamp});
            $params->remove('_');
            $next->query(build_urlencoded($params->flatten));
            $response{nextPage} = "$next";
        }

        return [200, ['Content-Type', 'application/json'], [
            encode_utf8(to_json(\%response)),
        ]];
    };

    mount "/subscribe" => sub {
        my $env = shift;
        my $req = Plack::Request->new($env);
        $env->{'plack.skip-deflater'} = 1;

        my @types;

        for my $type ($req->param('type')) {
            push @types, $type, $database->subtypes($type);
        }

        if (!@types) {
            @types = (0);
        }

        return sub {
            my $responder = shift;
            my $writer = $responder->([200, ['Content-Type' => 'application/json', 'Cache-control' => 'private, max-age=0, no-store']]);

            for my $type (uniq @types) {
                push @{ $Subscribers{$type} }, $writer;
            }
        };
    };
};

$server->register_service($app);

AE::cv->recv;
