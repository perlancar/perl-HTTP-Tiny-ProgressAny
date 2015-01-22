package HTTP::Tiny::ProgressAny;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Number::Format::Metric qw(format_metric);
use Progress::Any;
use Scalar::Util qw(refaddr);

use parent 'HTTP::Tiny';

sub __get_task_name {
    my $resp = shift;

    # each response hash has its own task, so we don't have problem with
    # parallel downloads
    my $task = __PACKAGE__; $task =~ s/::/./g;
    $task .= ".R" . refaddr($resp);
    $task;
}

sub _data_callback {
    my ($self, $url, $data, $resp) = @_;

    my $task = __get_task_name($resp);

    my $progress = Progress::Any->get_indicator(task=>$task);
    unless ($self->{_pa_data}{set_target}{"$resp"}++) {
        $progress->pos(0);
        if (my $cl = $resp->{headers}{'content-length'}) {
            $progress->target($cl);
        }
    }
    my $new_pos = $progress->pos() + length($data);
    my $target = $progress->target;
    if ($target && $new_pos >= $target) {
        $progress->finish;
        # cleanup so the number of tasks can be kept low. XXX we should do this
        # via API.
        no warnings 'once';
        delete $Progress::Any::indicators{$task};
        delete $self->{_pa_data}{set_target}{"$resp"};
    } else {
        $progress->update(
            pos => $new_pos,
            message => sub {
                my @msg = (
                    "Downloading ", $url, " ",
                    format_metric($new_pos),
                );
                if ($progress->target) {
                    push @msg, "/", format_metric($progress->target);
                }
                # XXX show speed
                join "", @msg;
            },
        );
    }
}

sub request {
    my ($self, $method, $url, $options0) = @_;

    my $options = { %{ $options0 // {}} }; # shallow copy

    my $orig_data_callback = $options->{data_callback};
    $options->{data_callback} = sub {
        $self->_data_callback($url, @_);
        $orig_data_callback->(@_) if $orig_data_callback;
    };

    $self->SUPER::request($method, $url, $options);
}

1;
# ABSTRACT: See progress for your HTTP::Tiny requests

=head1 SYNOPSIS

 use HTTP::Tiny::ProgressAny;
 use Progress::Any::Output;

 Progress::Any::Output->set("TermProgressBarColor");
 my $resp = HTTP::Tiny->new->get("http://example.com/some-big-file");
 # you will see a progress bar in your terminal


=head1 DESCRIPTION

This class is a subclass of L<HTTP::Tiny> that uses L<Progress::Any> to let you
see progress during HTTP requests.

Sample output:

=begin HTML

<img src="" />

=end HTML


=head1 SEE ALSO

L<LWP::UserAgent::ProgressAny>
