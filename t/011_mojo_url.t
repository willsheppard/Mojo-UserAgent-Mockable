use 5.014;

use Mojo::Util qw/slurp/;
use File::Temp;
use FindBin qw($Bin);
use Mojo::JSON qw(encode_json decode_json);
use Mojo::UserAgent::Mockable;
use Mojolicious::Quick;
use Test::Most;
use Test::Mojo;
use TryCatch;

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

my $original_host   = $url->host;
my $original_scheme = $url->scheme;
my $original_port   = $url->port;

my $output_file = qq{$dir/output.json};

my $transaction_count = 3;
# Record the interchange
my ( @results, @transactions );
{    # Look! Scoping braces!
    my $mock = Mojo::UserAgent::Mockable->new( mode => 'record', file => $output_file );
    $mock->transactor->name('kit.peters@broadbean.com');

    for ( 1 .. $transaction_count ) {
        push @transactions, $mock->get( $url->clone->query( [ quux => int rand 1e9 ] ));
    }

    @results = map { [ split /\n/, $_->res->text ] } @transactions;

    plan skip_all => 'Remote not responding properly'
        unless ref $results[0] eq 'ARRAY' && scalar @{ $results[0] } == $COUNT;
    $mock->save;
}

BAIL_OUT('Output file does not exist') unless ok(-e $output_file, 'Output file exists');

my $mock = Mojo::UserAgent::Mockable->new( mode => 'playback', file => $output_file );
$mock->transactor->name('kit.peters@broadbean.com');

my @mock_results;
my @mock_transactions;

# my $t = Test::Mojo->new;
for ( 0 .. $#transactions ) {
    my $transaction = $transactions[$_];
    my $result      = $results[$_];

    my $url = $transaction->req->url;

    my $mock_transaction = $mock->get( $url );

    is $url->host,   $original_host,   q{Host unchanged};
    is $url->scheme, $original_scheme, q{Scheme unchanged};
    is $url->port,   $original_port,   q{Port unchanged};
}

done_testing;

