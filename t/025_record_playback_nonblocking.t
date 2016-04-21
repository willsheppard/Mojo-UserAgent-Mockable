use 5.014;

use Mojo::Util qw/slurp/;
use File::Temp;
use FindBin qw($Bin);
use Mojo::IOLoop;
use Mojo::JSON qw(encode_json decode_json);
use Mojo::UserAgent::Mockable;
#use Mojo::UserAgent::Mockable::Serializer;
use Mojolicious::Quick;
use Path::Tiny;
use Test::Most;
use TryCatch;

my $ver;
eval { 
    require IO::Socket::SSL; 
    $ver = $IO::Socket::SSL::VERSION; 
    1;
} or plan skip_all => 'IO::Socket::SSL not installed';

plan skip_all => qq{Minimum version of IO::Socket::SSL is 1.94 for this test, but you have $ver} if $ver < 1.94;


my $TEST_FILE_DIR = qq{$Bin/files};
my $COUNT         = 5;
my $MIN           = 0;
my $MAX           = 1e9;
my $COLS          = 1;
my $BASE          = 10;

my $dir = File::Temp->newdir;

my $url = Mojo::URL->new(q{https://www.random.org/integers/})->query(
    num    => $COUNT,
    min    => $MIN,
    max    => $MAX,
    col    => $COLS,
    base   => $BASE,
    format => 'plain',
);

my $output_file = qq{/tmp/output.json};

my $transaction_count = 10;
my @urls = map { $url->clone->query( [ quux => int rand 100, count => $_ ] ) } ( 1 .. $transaction_count );

my (@transactions, @results);


# Record the interchange
{    # Look! Scoping braces!
    diag 'Recording begins';
    my @steps;
    for ( 0 .. $transaction_count ) {
        my $url = shift @urls;

        push @steps, sub {
            my ($delay, $tx) = @_;
            my $mock = $delay->data->{mock};
            $mock->get($url, $delay->begin) if $url;
            return unless ref $tx;
            push @transactions, $tx;
        };
    }

    my $mock = Mojo::UserAgent::Mockable->new( mode => 'record', file => $output_file );
    $mock->transactor->name('kit.peters@broadbean.com');
    my $delay = Mojo::IOLoop->delay;
    $delay->data(mock => $mock);
    $delay->steps( @steps );
    $delay->on( finish => sub { $mock->save; } );
    Mojo::IOLoop->client( { port => 3000 } => $delay->begin );
    $delay->wait;

    @results = map { [ split /\n/, $_->res->text ] } @transactions;
    BAIL_OUT('Output file does not exist') unless ok(-e $output_file, 'Output file exists');
    BAIL_OUT('Did not get all transactions') unless scalar @transactions == $transaction_count;

    diag 'Recording complete';
}

diag 'Playback begins';

my $mock = Mojo::UserAgent::Mockable->new( mode => 'playback', file => $output_file );
$mock->transactor->name('kit.peters@broadbean.com');

my @keep_results = map { [ @{$_} ] } @results;;

my @txns = Mojo::UserAgent::Mockable::Serializer->new->deserialize(path($output_file)->slurp_raw);

my @steps;
for my $index ( 0 .. $transaction_count ) {
    my $transaction = $transactions[$index];
    my $url         = $transaction ? $transaction->req->url->clone : undef;
    push @steps, sub {
        my ( $delay, $tx ) = @_;
        # $tx is the _previous_ transaction
        
        my $mock = $delay->data->{mock};
        $mock->get( $url, $delay->begin ) if $url;
        return unless ref $tx;

        diag qq{TXN $index}; 
        my $result      = $results[$index - 1];
        my $mock_result = [ split /\n/, $tx->res->text ];
        is $tx->res->headers->header('X-MUA-Mockable-Regenerated'), 1,
            'X-MUA-Mockable-Regenerated header present and correct';
        my $headers = $tx->res->headers->to_hash;
        #delete $headers->{'X-MUA-Mockable-Regenerated'};
        is_deeply( $mock_result, $result, q{Result correct} );
        is_deeply( $headers, $tx->res->headers->to_hash, q{Response headers correct} );
    };
}

my $err;
my $delay = Mojo::IOLoop->delay;
$delay->data( mock => $mock );
$delay->on( finish => sub { diag "Playback complete" } );
$delay->steps(@steps);
Mojo::IOLoop->client( { port => 3000 } => $delay->begin );
$delay->catch(
    sub {
        ( my $e, $err ) = @_;
        diag qq{Caught error: $err};
        fail;
    }
);
$delay->wait;
BAIL_OUT qq{Caught error in playback: $err} if $err;

subtest 'null on unrecognized (nonblocking)' => sub {
    my $mock = Mojo::UserAgent::Mockable->new( mode => 'playback', file => $output_file, unrecognized => 'null' );

    my $transaction = $transactions[$#transactions];

    lives_ok {
        $mock->get(
            $transaction->req->url->clone,
            sub {
                my ( $ua, $tx ) = @_;
                is $tx->res->text, '', qq{Request out of order returned null};
                Mojo::IOLoop->stop;
            }
        );
    }
    qq{GET did not die};
    Mojo::IOLoop->start;
};

subtest 'exception on unrecognized (nonblocking)' => sub {
    my $mock = Mojo::UserAgent::Mockable->new( mode => 'playback', file => $output_file, unrecognized => 'exception' );

    my $transaction = $transactions[$#transactions];

    throws_ok {
        $mock->get(
            $transaction->req->url->clone,
            sub {
                Mojo::IOLoop->stop;
            }
        )
    }
    qr/^Unrecognized request: URL query mismatch/;
};

subtest 'fallback on unrecognized (nonblocking)' => sub {
    my $mock = Mojo::UserAgent::Mockable->new( mode => 'playback', file => $output_file, unrecognized => 'fallback' );

    my $transaction = $transactions[$#transactions];
    my $result      = $results[$#results];
    lives_ok {
        $mock->get(
            $transaction->req->url->clone,
            sub {
                my ( $ua, $tx ) = @_;
                my $mock_result = [ split /\n/, $tx->res->text ];
                is scalar @{$mock_result}, scalar @{$result}, q{Result counts match};
                for ( 0 .. $#{$result} ) {
                    isnt $mock_result->[$_], $result->[$_], qq{Result $_ does NOT match};
                }
                Mojo::IOLoop->stop;
            }
        );
    }
    qq{GET did not die};
    Mojo::IOLoop->start;

};

done_testing;
