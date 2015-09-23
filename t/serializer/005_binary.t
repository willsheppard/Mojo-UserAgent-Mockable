use 5.014;
use File::Temp;
use FindBin qw($Bin);
use File::Compare qw(compare);
use File::Spec;
use Test::Most;
use Mojo::Message::Serializer;
use Mojolicious;

my $serializer = Mojo::Message::Serializer->new;
my $file = qq{$Bin/../files/sample resume.docx};

my $action = sub {
    my $c = shift;

    my ($dir, $filename) = (File::Spec->splitpath($file))[1..2];
    push @{$c->app->static->paths}, $dir; 
    $c->res->headers->content_disposition('attachment; filename=sample_resume.docx');
    $c->reply->static($filename);
};

my $app = Mojolicious->new;
$app->routes->any(
    '/*any' => { any => '' } => $action
);
my $ua = $app->ua;
my $tx = $ua->get('/download');
my $serialized = $serializer->serialize($tx->res);
$tx = undef;
$app = undef;

my $dir = File::Temp->newdir;
my $download = qq{$dir/sample_resume.docx};

my $res2 = $serializer->deserialize($serialized);
$res2->content->asset->move_to($download);

is compare($download, $file), 0, 'Binary files copied properly';
done_testing;
