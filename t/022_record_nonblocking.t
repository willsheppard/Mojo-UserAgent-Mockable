use 5.014;

use File::stat;
use File::Temp;
use Mojo::UserAgent::Mockable;
use Mojo::UserAgent::Mockable::Serializer;
use Test::Most;

my $dir = File::Temp->newdir;

my @transactions;
push @transactions, Mojo::UserAgent->new->get(q{http://www.vam.ac.uk/api/json/museumobject/O1}), Mojo::UserAgent->new->get(q{http://www.vam.ac.uk/api/json/museumobject/O1}); 

my @results = map { $_->res->json } @transactions;

BAIL_OUT('Museum API not responding properly') unless $results[0]->[0]->{'pk'} == 1773;

my $output_file = qq{$dir/victoria_and_albert.json};

my $mock = Mojo::UserAgent::Mockable->new( mode => 'record', file => $output_file );
for ( 0 .. $#transactions ) {
    my $result_from_mock;
    my $index = $_;
    lives_ok {
        $mock->get(
            $transactions[$_]->req->url->clone,
            sub {
                my ( $ua, $tx ) = @_;
                is_deeply $tx->res->json, $results[$index], qq{result $index matches that of stock Mojo UA (nonblocking)};
                Mojo::IOLoop->stop_gracefully if Mojo::IOLoop->is_running;
            }
        );
    }
    'get() did not die (nonblocking)';
}
Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
$mock->save;

ok -e $output_file, 'Output file exists';
isnt stat($output_file)->size, 0, 'Output file has nonzero size';
my @deserialized = Mojo::UserAgent::Mockable::Serializer->new->retrieve($output_file);

is scalar @deserialized, scalar @transactions, 'Transaction count matches';
done_testing;
