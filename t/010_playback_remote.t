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
my $COUNT = 5;
my $MIN = 0;
my $MAX = 1e9;
my $COLS = 1;
my $BASE = 10;

subtest 'Random.org' => sub {
    do_test( url => q{https://www.random.org/integers/} );
};

subtest 'Local app' => sub {
    my $app = get_local_random_app();
    do_test( url => q{/integers}, app => $app );
};

sub do_test {
    my %args = @_;

    my $dir = File::Temp->newdir;

    my $url = Mojo::URL->new( $args{'url'} )->query(
        num    => $COUNT,
        min    => $MIN,
        max    => $MAX,
        col    => $COLS,
        base   => $BASE,
        format => 'plain',
    );
    my $app = $args{'app'};

    my $output_file = qq{$dir/output.json};

    # Record the interchange
    my (@results, @transactions);
    { # Look! Scoping braces!
        my $mock = Mojo::UserAgent::Mockable->new( mode => 'record', file => $output_file );
        $mock->transactor->name('kit.peters@broadbean.com');
        if ($app) {
            $mock->server->app($app);
        }
        push @transactions, $mock->get($url->clone->query( [ quux => 'alpha' ] ));
        push @transactions, $mock->get($url->clone->query( [ quux => 'beta' ] ));

        @results = map { [ split /\n/, $_->res->text ] } @transactions;

        plan skip_all => 'Remote not responding properly' unless ref $results[0] eq 'ARRAY' && scalar @{$results[0]} == $COUNT;
        $mock->save;
    }

    SKIP: {
        skip 'Output file does not exist', 1 unless ok(-e $output_file, 'Output file exists');

        my $mock = Mojo::UserAgent::Mockable->new( mode => 'playback', file => $output_file );
        $mock->transactor->name('kit.peters@broadbean.com');
        if ($app) {
            $mock->server->app($app);
        }
        my @mock_results;
        my @mock_transactions;

        for (0 .. $#transactions) {
            my $transaction = $transactions[$_];
            my $result      = $results[$_];

            my $mock_transaction = $mock->get( $transaction->req->url );
            my $mock_result = [ split /\n/, $mock_transaction->res->text ];
            my $mock_headers = $mock_transaction->res->headers->to_hash;
            is $mock_headers->{'X-MUA-Mockable-Regenerated'}, 1, 'X-MUA-Mockable-Regenerated header present and correct';
            delete $mock_headers->{'X-MUA-Mockable-Regenerated'};

            is_deeply( $mock_result, $result, q{Result correct} );
            is_deeply(
                $mock_headers,
                $transaction->res->headers->to_hash,
                q{Response headers correct}
            );
        }

        subtest 'Reverse order' => sub {
            # TODO: making requests out of order should either produce a null output, an exception, or fall back to the internet.
            # Probably add a configurable behavior on that.
            #
            # Future feature: add a callback for unrecognized requests
            my $mock = Mojo::UserAgent::Mockable->new( mode => 'playback', file => $output_file, unrecognized => 'null' );
            if ($app) {
                $mock->server->app($app);
            }

            for (0 .. $#transactions) {
                my $index = $#transactions - $_;
                my $transaction = $transactions[$index];

                my $mock_transaction;
                lives_ok { $mock_transaction = $mock->get($transaction->req->url) } q{GET did not die};
                is $mock_transaction->res->text, '', q{Request out of order returned null};
            }
            
            $mock = Mojo::UserAgent::Mockable->new( mode => 'playback', file => $output_file, unrecognized => 'exception' );
            if ($app) {
                $mock->server->app($app);
            }
            for (0 .. $#transactions) {
                my $index = $#transactions - $_;
                my $transaction = $transactions[$index];

                dies_ok { $mock->get($transaction->req->url) } q{GET died};
            }

            $mock = Mojo::UserAgent::Mockable->new( mode => 'playback', file => $output_file, unrecognized => 'fallback' );
            if ($app) {
                $mock->server->app($app);
            }
            for (0 .. $#transactions) {
                my $index = $#transactions - $_;
                my $transaction = $transactions[$index];
                my $result = $results[$index];

                my $tx;
                lives_ok { $tx = $mock->get($transaction->req->url) } q{GET did not die};
                my $mock_result = [ split /\n/, $tx->res->text ];
                for ( 0 .. $#{$result} ) {
                    isnt $mock_result->[$_], $result->[$_], qq{Result $_ does NOT match};
                }
            }
        };
    }
};

sub get_local_random_app {
    my $app = Mojolicious->new;
    $app->routes->get(
        '/integers' => sub {
            my $c     = shift;
            my $count = $c->req->param('num') || 1;
            my $min   = $c->req->param('min') || 0;
            my $max   = $c->req->param('max') || 1e9;
            my $cols  = $c->req->param('cols') || 1;

            my @nums;
            for ( 0 .. ( $count - 1 ) ) {
                my $number = ( int rand( $max - $min ) ) + $min;
                push @nums, $number;
            }

            $c->render( text => join qq{\n}, @nums );
        },
    );
    return $app;
}

done_testing;
