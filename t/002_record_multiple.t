use 5.014;

use File::Slurp qw/slurp/;
use File::Temp;
use FindBin qw($Bin);
use Mojo::JSON qw(encode_json decode_json);
use Mojo::UserAgent::Mockable;
use Mojolicious::Quick;
use Test::Most;
use TryCatch;

my $TEST_FILE_DIR = qq{$Bin/files};
my $vanilla_ua = Mojo::UserAgent->new();

subtest 'Victoria and Albert Museum' => sub {
    my $dir = File::Temp->newdir;
   
    my @transactions;
    push @transactions, Mojo::UserAgent->new->get(q{http://www.vam.ac.uk/api/json/museumobject/?limit=1});

    my $result = $transactions[0]->res->json;

    plan skip_all => 'Museum API not responding properly' unless ref $result eq 'HASH' && $result->{'meta'};
    plan skip_all => 'No records returned' unless @{$result->{'records'}};

    my $object_number = $result->{'records'}[0]{'fields'}{'object_number'};

    push @transactions, Mojo::UserAgent->new->get(qq{http://www.vam.ac.uk/api/json/museumobject/$object_number}); 
    my $museum_object = $transactions[1]->res->json;

    plan skip_all => 'Museum object not retrieved properly' unless @{$museum_object} && keys %{$museum_object->[0]};

    my $output_file = qq{$dir/victoria_and_albert.json};
    
    { # Look! Scoping braces!
        my $mock = Mojo::UserAgent::Mockable->new( mode => 'record', file => $output_file );
        my $result_from_mock;
        lives_ok { $result_from_mock = $mock->get( $transactions[0]->req->url )->res->json; } 'get() did not die';
        is_deeply( $result_from_mock, $result, 'result matches that of stock Mojo UA' );
        my $museum_object_from_mock = Mojo::UserAgent->new->get($transactions[1]->req->url)->res->json;
        is_deeply($museum_object_from_mock, $museum_object, q{Museum object matches that of stock Mojo UA});
    }
    
    SKIP: {
        skip 'Output file does not exist' unless ok(-e $output_file, 'Output file exists');
        my $recording = slurp($output_file);

        my $interchange;
        try {
            $interchange = decode_json($recording);
        } 
        catch ($exception) {
            skip qq{Caught exception decoding JSON: $exception};
        }

        skip 'Recording not stored as array' unless is( ref $interchange, 'ARRAY');

        is (scalar @{$interchange}, 2, 'Two transactions in the interchange');
        for ( 0 .. $#{$interchange}) {
            my $recorded_transaction = $interchange->[$_];
            my $original_transaction = $transactions[$_];

            is $recorded_transaction->{'request'}{'class'}, 'Mojo::Message::Request', 'Request class correct';
            is $recorded_transaction->{'response'}{'class'}, 'Mojo::Message::Response', 'Response class correct';

            my $request  = Mojo::Message::Request->new->parse( $recorded_transaction->{'request'}{'body'} );
            my $response = Mojo::Message::Response->new->parse( $recorded_transaction->{'response'}{'body'} );

            is $request->url, $original_transaction->req->url, q{Request URL correct};
            is_deeply($response->json, $original_transaction->res->json, q{Response data correct});
        }
    }
};

subtest 'Local App' => sub {
    my $dir = File::Temp->newdir;

    my $app = Mojolicious::Quick->new(
        GET => [
            '/records' => sub {
                my $c = shift;
                $c->render(
                    json => {
                        meta    => { count => 1, },
                        records => [
                            {   id      => 8675309,
                                author  => 'Tommy Tutone',
                                subject => 'Jenny',
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
    );

    my @transactions = $app->ua->get(q{/records});
     
    my $records = $transactions[0]->res->json;
    my $record_id = $records->{'records'}[0]{'id'};
    push @transactions,  $app->ua->get(qq{/record/$record_id});
    my $record = $transactions[1]->res->json;

    BAIL_OUT('Local app did not serve records correctly') unless $transactions[1]->res->json->[0]{'author'} eq 'Tommy Tutone';

    my $output_file = qq{$dir/local_app.json};
    { # Look! Scoping braces!
        my $mock = Mojo::UserAgent::Mockable->new( mode => 'record', file => $output_file );
        $app->ua($mock);

        my $records_from_mock;
        lives_ok { $records_from_mock = $mock->get( $transactions[0]->req->url )->res->json; } 'get() did not die';
        is_deeply( $records_from_mock, $records, 'records match that of stock Mojo UA' );
        my $record_from_mock = Mojo::UserAgent->new->get($transactions[1]->req->url)->res->json;
        is_deeply($record_from_mock, $record, q{Single record matches that of stock Mojo UA});
    }

    SKIP: {
        skip 'Output file does not exist' unless ok(-e $output_file, 'Output file exists');
        my $recording = slurp($output_file);

        my $interchange;
        try {
            $interchange = decode_json($recording);
        } 
        catch ($exception) {
            skip qq{Caught exception decoding JSON: $exception};
        }

        skip 'Recording not stored as array' unless is( ref $interchange, 'ARRAY');

        is (scalar @{$interchange}, 2, 'Two transactions in the interchange');
        for ( 0 .. $#{$interchange}) {
            my $recorded_transaction = $interchange->[$_];
            my $original_transaction = $transactions[$_];

            is $recorded_transaction->{'request'}{'class'}, 'Mojo::Message::Request', 'Request class correct';
            is $recorded_transaction->{'response'}{'class'}, 'Mojo::Message::Response', 'Response class correct';

            my $request  = Mojo::Message::Request->new->parse( $recorded_transaction->{'request'}{'body'} );
            my $response = Mojo::Message::Response->new->parse( $recorded_transaction->{'response'}{'body'} );

            is $request->url, $original_transaction->req->url, q{Request URL correct};
            is_deeply($response->json, $original_transaction->res->json, q{Response data correct});
        }
    }
};

done_testing;

