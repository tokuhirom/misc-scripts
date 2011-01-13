#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use AE;
use Cocoa::EventLoop;

PikuboGrowler->new()->run();
AE::cv()->recv();

{
    package PikuboGrowler;
    use Log::Minimal;
    use JSON;
    use Furl;
    use Cocoa::Growl ':all';
    use AnyEvent::HTTP;
    use Class::Accessor::Lite (
        ro => [qw/furl url deduper interval/],
    );

    sub new {
        my $class = shift;
        my %args = @_==1 ? %{$_[0]} : @_;

        growl_running() or die "growl is not running under this machine";

        growl_register(
            app  => 'PikuboGrowler',
            icon => 'http://www.gravatar.com/avatar/0d2a86f4099d096a4a6a9d1eb977bf38?r=g&s=80&d=http%3A%2F%2Fst.pimg.net%2Ftucs%2Fimg%2Fwho.png',    # or 'http://url/to/icon'
            notifications => [qw(Notification1)],
        );

        bless {
            url   => 'http://pikubo.jp/api/v1/public_feed.json',
            interval => 60,
            furl  => Furl->new(),
            deduper => PikuboGrowler::Deduper->new(limit => 50),
            %args,
        }, $class;
    }

    sub run {
        my $self = shift;

        $self->{timer} = AE::timer 0, $self->interval, sub {
            infof("run once");
            $self->run_once;
        };
    }

    sub run_once {
        my $self = shift;

        my $pikubo_api_url = $self->url // die;
        infof("access to $pikubo_api_url");
        $self->{request} = http_get $pikubo_api_url, timeout => 10, sub {
            my ($data, $headers) = @_;
            debugf("got response");

            if ($headers->{Status} eq 200) {
                infof("got normal response");
                my $rows = eval { decode_json($data) } or do {
                    critf("Cannot parse json: %s", $@);
                    return;
                };

                for my $row (@$rows) {
                    my $url= $row->{url} // die;
                    debugf("process %s", $url);
                    my $title = $row->{user_name} // die "fucking user name";
                    my $description = $row->{description} // die "fucking user name";
                    $self->deduper->check($url) and do {
                        infof("growl %s", $url);
                        (my $photo_url = $url) =~ s!/photo/!/p/p/!;
                        growl_notify(
                            name        => 'Notification1',
                            title       => $title,
                            description => $description,
                            icon        => $photo_url,
                            on_click    => sub { system 'open', $url }
                        );
                    };
                }
            } else {
                warnf("code is not a 200: %s", ddf($headers));
            }
        };
    }
}

{
    package PikuboGrowler::Deduper;
    sub new {
        my $class = shift;
        my %args = @_==1 ? %{$_[0]} : @_;
        bless +{ data => [], limit => 100, %args }, $class;
    }
    sub check {
        my ($self, $k) = @_;
        for (@{$self->{data}}) {
            if ($_ eq $k) {
                return 0; # duped
            }
        }
        push @{$self->{data}}, $k;
        return 1;
    }
}
