use 5.014;
use Test::Most;
use Mojo::Message::Request;
use Mojo::Transaction::HTTP;
use Mojo::UserAgent::Mockable;

sub tx {
    return Mojo::Transaction::HTTP->new(
        req => Mojo::Message::Request->new( @_ ),
    );
}

subtest 'no sub' => sub {

    my $ua = Mojo::UserAgent::Mockable->new();

    my $tx          = tx( method => 'GET', url => '/integers/3432' );
    my $recorded_tx = tx( method => 'GET', url => '/integers/6345' );
    my ($this_req, $recorded_req) = $ua->_normalized_req( $tx, $recorded_tx );

    is(
        $this_req,
        $tx->req,
        "No normalizer, just pass through the requests"
    );
    is(
        $recorded_req,
        $recorded_tx->req,
        "No normalizer, just pass through the requests"
    );

};

done_testing;
