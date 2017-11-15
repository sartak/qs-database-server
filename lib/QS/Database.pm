package QS::Database;
use 5.14.0;
use Moose;
use DBI;

has _dbh => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        my $dbh = DBI->connect(
            "dbi:SQLite:dbname=" . shift->file,
            undef,
            undef,
            { RaiseError => 1 },
        );
        $dbh->{sqlite_unicode} = 1;
        $dbh
    },
);

has file => (
    is      => 'ro',
    isa     => 'Str',
    default => 'qs.sqlite',
);

sub authenticate {
    my $self = shift;
    my $username = shift;
    my $password = shift;

    my $query = 'SELECT name FROM users WHERE name=? AND password=?;';
    my $sth = $self->_dbh->prepare($query);
    $sth->execute($username, $password);

    return $sth->fetchrow_array ? 1 : 0;
}

sub insert {
    my $self = shift;
    my %args = @_;

    my $sth = $self->_dbh->prepare("INSERT INTO events (timestamp, type, uri, metadata, isDiscrete, isStart, otherEndpoint, duration) VALUES (?, ?, ?, ?, ?, ?, NULL, NULL);");

    $args{timestamp} = time if $args{timestamp} eq 'now';

    if ($args{isDiscrete}) {
        delete $args{isStart};
    }
    else {
        $args{isStart} = 1;
    }

    $sth->execute(@args{qw/timestamp type uri metadata isDiscrete isStart/});

    return $self->_dbh->sqlite_last_insert_rowid;
}

sub finish_event {
    my $self = shift;
    my %args = @_;

    $self->_dbh->begin_work;

    my ($start_timestamp, $start_type, $existing_endpoint) = $self->_dbh->selectrow_array("SELECT timestamp, type, otherEndpoint FROM events WHERE id=?", {}, $args{otherEndpoint});

    if ($existing_endpoint) {
        $self->_dbh->rollback;
        return 0;
    }

    $args{timestamp} = time if $args{timestamp} eq 'now';
    $args{isDiscrete} = 0;
    $args{isStart} = 0;
    $args{duration} //= $args{timestamp} - $start_timestamp;
    $args{type} //= $start_type;

    $self->_dbh->do(
        "INSERT INTO events (timestamp, type, uri, metadata, isDiscrete, isStart, otherEndpoint, duration) VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
        {},
        @args{qw/timestamp type uri metadata isDiscrete isStart otherEndpoint duration/}
    );

    my $id = $self->_dbh->sqlite_last_insert_rowid;

    $self->_dbh->do(
        "UPDATE events SET isDiscrete=0, isStart=1, otherEndpoint=?, duration=? WHERE id=?",
        {},
        $id, $args{duration}, $args{otherEndpoint},
    );

    $self->_dbh->commit;

    return $id;
}

sub event_types {
    my $self = shift;

    my @types = $self->_dbh->selectall_array("SELECT id, parent, label, tags, materialized_path FROM event_types;");
    my %tree;
    my @parents = [0, \%tree];
    while (@parents) {
        my ($parent_id, $parent_tree) = @{ shift @parents };
        my @children = grep { $_->[1] == $parent_id } @types;
        @types = grep { $_->[1] != $parent_id } @types;

        for (@children) {
            my ($id, undef, $label, $tags, $materialized_path) = @$_;
            my %subtree = (
                label => $label,
                tags => $tags,
                materialized_path => $materialized_path,
            );
            $parent_tree->{$id} = \%subtree;
            push @parents, [$id, \%subtree];
        }
    }

    return \%tree;
}

sub subtypes {
    my $self = shift;
    my $type = shift;

    return map { $_->[0] } $self->_dbh->selectall_array("SELECT child.id FROM event_types AS child JOIN event_types AS parent ON child.materialized_path LIKE parent.materialized_path || '%' WHERE parent.id=? AND child.id != parent.id;", {}, $type);
}

sub events {
    my $self = shift;
    my %args = (
        count  => 1000,
        id     => undef,
        type   => undef,
        before => undef,
        fields => [],
        @_,
    );

    my @bind;
    my @where;

    my @fields = grep { /^[a-zA-Z_]+$/ } map { split /\s*,\s*/ } @{ $args{fields} };
    @fields = ('id', 'timestamp', 'type', 'uri', 'metadata', 'isDiscrete', 'isStart', 'otherEndpoint', 'duration') unless @fields;

    my $query = "SELECT ".(join ", ", map { "events.$_" } @fields)." FROM events";

    if ($args{type}) {
        $query .= " JOIN event_types ON events.type = event_types.id ";
        push @where, "event_types.materialized_path LIKE (SELECT (materialized_path || '%') FROM event_types WHERE id=?)";
        push @bind, $args{type};
    }

    if ($args{before}) {
        push @where, "events.timestamp < ?";
        push @bind, $args{before};
    }

    if ($args{id}) {
        push @where, "events.id = ?";
        push @bind, $args{id};
    }

    $query .= " WHERE " . join(" AND ", @where)
        if @where;

    $query .= " ORDER BY events.timestamp DESC";

    if ($args{count}) {
        $query .= " LIMIT ?";
        push @bind, $args{count};
    }

    my $sth = $self->_dbh->prepare($query);
    $sth->execute(@bind);

    my @results;
    while (my $row = $sth->fetchrow_hashref) {
        push @results, $row;
    }
    return @results;
}

1;

