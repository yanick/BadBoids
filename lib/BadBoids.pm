package BadBoids;
use Dancer ':syntax';

our $VERSION = '0.1';

use DBIx::NoSQL;
use Data::Printer;
use List::AllUtils qw/ uniq /;

use Dancer::Plugin::Auth::Twitter;
use Dancer::Plugin::Auth::Extensible;
use DateTime::Format::Flexible;
use DateTime::Duration::Fuzzy qw/ time_ago /;
use DateTime::Format::Human::Duration;
use DateTime::Functions qw/ now /;

auth_twitter_init();

my $store = DBIx::NoSQL->connect(['dbi:SQLite:budgerigars.sqlite', undef,
        undef, { sqlite_unicode => 1 } ]);

#$store->model('Status')->index('id');
$store->model('Status')->index('budgie_profile');
$store->model('Status')->index('budgie_timeline');
$store->model('Status')->index('created_at', isa => 'DateTime');

$store->model('Profile')->index('budgie_user');
#$store->model('Status')->reindex;

hook before => sub {
    redirect '/login' unless logged_in_user() 
        or request->path eq '/login';
};

get '/' => sub {
    return template 'profiles' => {
        auth_url => auth_twitter_authenticate_url,
        user => logged_in_user(),
        profiles => [
            $store->search( Profile => {
                budgie_user => logged_in_user()->{user}
            })->all
        ],
    };
};

get '/authorized' => sub {
    my $profile = session('twitter_user');

    $profile->{budgie_user} = logged_in_user()->{user};

    $store->set( Profile => $profile->{screen_name} => $profile );

    redirect "/profile/" . $profile->{screen_name};
};

0 and get '/profile/:profile' => sub {
    my $profile = $store->get( Profile => param('profile') );

    my $twitter = Net::Twitter->new(
        traits   => [qw/API::RESTv1_1/],
        consumer_key        => config->{plugins}{'Auth::Twitter'}{consumer_key},
        consumer_secret     => config->{plugins}{'Auth::Twitter'}{consumer_secret},
        access_token        => $profile->{access_token},
        access_token_secret => $profile->{access_token_secret},
    );

    return $twitter->home_timeline( { count => 1 } );
};

get '/profile/:profile' => sub {
    template 'profile';
};

sub get_profile {
    my $profile_name = param('profile');
    my $profile = $store->get( Profile => param('profile') );

    my $twitter = Net::Twitter->new(
        traits   => [qw/API::RESTv1_1/],
        consumer_key        => config->{plugins}{'Auth::Twitter'}{consumer_key},
        consumer_secret     => config->{plugins}{'Auth::Twitter'}{consumer_secret},
        access_token        => $profile->{access_token},
        access_token_secret => $profile->{access_token_secret},
    );

    return( $profile, $twitter );
}

get '/profile/:profile/timeline/:timeline' => sub {
    my( $profile, $twitter ) = get_profile(); 

    my $rs = $store->search( 'Status' => { 
        budgie_profile => $profile->{screen_name},
        budgie_timeline => param('timeline'),
    } )->order_by( 'created_at DESC' );

    my $max_count = 50;

    my @status;
    my $after = param('after');
    debug "after is $after";
    while( my $s = $rs->next ) {
        debug "status " . $s->{id_str};
        last if $after and $after eq $s->{id_str};
        push @status, $s;
        $max_count-- or last;
    }

    my %user;
    my $fmt = DateTime::Format::Human::Duration->new;
    my $now = now();

    for ( @status ) {
        $_->{user} = 
            ${user}{$_->{user}{id_str}} 
                ||= $store->get('Twitter_User' => $_->{user}{id_str});

        $_->{created_at} = $fmt->format_duration_between( $now,
            $_->{created_at}, significant_units => 1 );
        $_->{created_at} =~ s/ (\S).*/$1/;

        $_->{text} =~ s#(http://[a-zA-Z0-9/.]+[a-zA-Z0-9/.])#<a href="$1">$1</a>#g;
    }

    return \@status;
};


sub fetch_updates {
    my ( $profile, $twitter, $timeline ) = @_;

    my $last = $store->search( 'Status' => {
        budgie_profile => $profile->{screen_name},
        budgie_timeline => $timeline,
    } )->order_by( 'created_at DESC' )->next;

    my $last_status_id = undef; #$last && $last->{id_str};

    my $max_count = 20;

    debug "Last $timeline status id: " . $last_status_id;

    my $method = $timeline . '_timeline';

    my @status = @{
        $twitter->$method({
            ( since_id => $last_status_id ) x !! $last_status_id,    
            count    => $max_count,
            trim_user => 1,
        })
    };

    for my $s ( @status ) {
        next if $store->exists( 'Status' => $s->{id_str} );
        $s->{budgie_profile}  = $profile->{screen_name},
        $s->{budgie_timeline} = $timeline,
        $s->{created_at} = DateTime::Format::Flexible->parse_datetime($s->{created_at});
        $store->set( 'Status' => $s->{id_str} => $s );
    }

    return {
        status => \@status,
        maybe_more => @status == $max_count,
    }
}

get '/profile/:profile/update' => sub {
    my( $profile, $twitter ) = get_profile(); 
    my $profile_name = $profile->{screen_name};

    my %updates;

    $updates{timeline}{home} = fetch_updates( $profile, $twitter, 'home' );
    $updates{timeline}{mentions} = fetch_updates( $profile, $twitter, 'mentions' );

    my @user_ids = uniq map { $_->{user}{id_str} } map { @$_ } map {
    $_->{status}  } values %{ $updates{timeline} };
    for my $u ( @user_ids ) {
        next if $store->exists( 'Twitter_User' => $u );
        my $user = $twitter->show_user({ user_id => $u }) or next;
        $store->set( 'Twitter_User' => $u => $user );
        push @{ $updates{twitter_users} }, $user;
    }

    return \%updates;
};

post '/status/:id/toggle' => sub {
    my $status = $store->get('Status'=>param('id'));
    $status->{budgie_hidden} = $status->{budgie_hidden} ? undef : '1';
    $store->set( Status => param('id') => $status ); 

    return { hidden => $status->{budgie_hidden} };
};

true;
