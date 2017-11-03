package QS::Middleware::Auth;
use strict;
use warnings;
use parent qw/Plack::Middleware/;

use Plack::Util::Accessor qw(dbh);
use Plack::Request;

sub call {
    my $self = shift;
    my $env  = shift;

    return $self->authenticate($env)
         ? $self->app->($env)
         : $self->unauthorized($env);
}

sub authenticate {
    my $self = shift;
    my $env  = shift;
    my $req  = Plack::Request->new($env);

    my $username = $req->header('X-QS-Username') || $req->param('user');
    my $password = $req->header('X-QS-Password') || $req->param('pass');

    my $query = 'SELECT name FROM users WHERE name=? AND password=?;';
    my $sth = $self->dbh->prepare($query);
    $sth->execute($username, $password);

    if (my ($name) = $sth->fetchrow_array) {
        $env->{'psgix.qs_user'} = $name;
        return 1;
    }

    return;
}

sub unauthorized {
    my $body = 'Authorization required';
    return [
        401,
        [
            'Content-Type'    => 'text/plain',
            'Content-Lentgth' => length $body,
        ],
        [$body],
    ];
}

1;

