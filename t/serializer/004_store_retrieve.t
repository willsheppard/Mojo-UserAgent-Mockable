use 5.014;
use File::Slurp qw(slurp);
use File::Temp;
use Test::Most;
use Test::JSON;
use Mojo::JSON;
use Mojo::Message::Request;
use Mojo::Message::Response;
use Mojo::UserAgent::Mockable::Serializer;
use Mojolicious::Quick;

my $serializer = Mojo::UserAgent::Mockable::Serializer->new;

subtest 'Victoria and Albert Museum' => sub {
    my $dir = File::Temp->newdir;
    my $output_file = qq{$dir/victoria_and_albert.json};

    my @transactions;
    push @transactions, Mojo::UserAgent->new->get(q{http://www.vam.ac.uk/api/json/museumobject/?limit=1});

    my $result = $transactions[0]->res->json;

    plan skip_all => 'Museum API not responding properly' unless ref $result eq 'HASH' && $result->{'meta'};
    plan skip_all => 'No records returned' unless @{$result->{'records'}};

    my $object_number = $result->{'records'}[0]{'fields'}{'object_number'};

    push @transactions, Mojo::UserAgent->new->get(qq{http://www.vam.ac.uk/api/json/museumobject/$object_number}); 
    my $museum_object = $transactions[1]->res->json;

    plan skip_all => 'Museum object not retrieved properly' unless @{$museum_object} && keys %{$museum_object->[0]};

    test_transactions($output_file, @transactions);
};

subtest 'Local App' => sub {
    my $app = get_local_app();
    my $dir = File::Temp->newdir;
    my $output_file = qq{$dir/local_app.json};

    my @transactions = $app->ua->get(q{/records});
     
    my $records = $transactions[0]->res->json;
    my $record_id = $records->{'records'}[0]{'id'};
    push @transactions,  $app->ua->get(qq{/record/$record_id});
    my $record = $transactions[1]->res->json;

    BAIL_OUT('Local app did not serve records correctly') unless $transactions[1]->res->json->[0]{'author'} eq 'Tommy Tutone';

    test_transactions($output_file, @transactions);
};

done_testing;

sub test_transactions {
    my ($output_file, @transactions) = @_;

    lives_ok { $serializer->store($output_file, @transactions) } q{serialize() did not die};

    my $serialized = slurp $output_file;
    is_valid_json($serialized, q{Serializer outputs valid JSON});

    my $deserialized = Mojo::JSON::decode_json($serialized);

    is ref $deserialized, 'ARRAY', q{Transactions serialized as array};
    for (0 .. $#transactions) {
        for my $key (qw/request response/) {
            ok defined($deserialized->[$_]{$key}), qq{Key "$key" defined in serial data};
            for my $subkey (qw/class body/) {
                ok defined($deserialized->[$_]{$key}{$subkey}), qq{Key "$subkey" defined in "$key" data};
            }
            my $expected_class = sprintf 'Mojo::Message::%s', ucfirst $key;
            is $deserialized->[$_]{$key}{'class'}, $expected_class, qq{"$key" class correct};
        }

        my $req = Mojo::Message::Request->new->parse($deserialized->[$_]{'request'}{'body'});
        my $res = Mojo::Message::Response->new->parse($deserialized->[$_]{'response'}{'body'});

        my %expected_headers = (
            request => $transactions[$_]->req->headers->to_hash,
            response => $transactions[$_]->res->headers->to_hash,
        );
        my %got_headers = (
            request => $req->headers->to_hash,
            response => $res->headers->to_hash,
        );

        for my $key (qw/request response/) {
            is_deeply($got_headers{$key}, $expected_headers{$key}, q{Headers correct});
        }

        is $req->url->path, $transactions[$_]->req->url->path, q{URL path correct};
        is $req->body, $transactions[$_]->req->body, q{Body correct};
        is_deeply $res->json, $transactions[$_]->res->json, q{Response encoded correctly};
    }

    my @deserialized = $serializer->retrieve($output_file);
    for (0 .. $#transactions) {
        my $deserialized_tx = $deserialized[$_];

        my $req = $deserialized_tx->req;
        my $res = $deserialized_tx->res;

        my %expected_headers = (
            request => $transactions[$_]->req->headers->to_hash,
            response => $transactions[$_]->res->headers->to_hash,
        );
        my %got_headers = (
            request => $req->headers->to_hash,
            response => $res->headers->to_hash,
        );

        for my $key (qw/request response/) {
            is_deeply($got_headers{$key}, $expected_headers{$key}, q{Headers correct (retrieve)});
        }

        is $req->url->path, $transactions[$_]->req->url->path, q{URL path correct (retrieve)};
        is $req->body, $transactions[$_]->req->body, q{Body correct (retrieve)};
        is_deeply $res->json, $transactions[$_]->res->json, q{Response encoded correctly (retrieve)};
    }

    return;
}

sub get_local_app {
    return Mojolicious::Quick->new(
        [   GET => [
                '/records' => sub {
                    my $c = shift;
                    $c->render(
                        json => {
                            meta    => { count => 1, },
                            records => [
                                {   id            => 8675309,
                                    author        => 'Tommy Tutone',
                                    subject       => 'Jenny',
                                    repercussions => 'Many telephone companies now refuse to give out the number '
                                        . '"867-5309".  People named "Jenny" have come to despise this song. '
                                        . 'Mr. Tutone made out well.',
                                }
                            ],
                        }
                    );
                },
                '/record/:id' => sub {
                    my $c  = shift;
                    my $id = $c->stash('id');
                    if ( $id eq '8675309' ) {
                        $c->render(
                            json => [
                                {   id            => 8675309,
                                    author        => 'Tommy Tutone',
                                    subject       => 'Jenny',
                                    repercussions => 'Many telephone companies now refuse to give out the number '
                                        . '"867-5309".  People named "Jenny" have come to despise this song. '
                                        . 'Mr. Tutone made out well.',
                                    summary => 'The singer wonders who he can turn to, and recalls Jenny, who he feels '
                                        . 'gives him something that he can hold on to.  He worries that she will '
                                        . 'think that he is like other men who have seen her name and number written '
                                        . 'upon the wall, but persists in calling her anyway. In his heart, the '
                                        . 'singer knows that Jenny is the girl for him.',
                                }
                            ]
                        );
                    }
                },
            ],
        ]
    );
}

__END__
