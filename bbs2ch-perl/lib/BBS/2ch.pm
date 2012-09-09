# Copyright (C) 2012 Tetsuya Kimata <kimata@green-rabbit.net>.

package BBS::2ch;

use utf8;

use strict;
use warnings;
use vars qw($VERSION);

use Encode;
use Encode::Guess qw/shiftjis euc-jp 7bit-jis/;

use Switch;
use URI;
use WWW::Mechanize;
use DateTime::Format::Strptime;

our $VERSION = '0.01';

use constant WAIT_SEC           => 1.1;
use constant GET_RETRY_COUNT    => 5;

use constant BBS_LIST_URL       => 'http://menu.2ch.net/bbstable.html';
use constant THREAD_LIST_FILE   => 'subject.txt';
use constant THREAD_URL_FORMAT  => 'http://%s.2ch.net/test/read.cgi/%s/%s/';

use constant CONTROL_FREE_BBS   => 'http://ula.cc/2ch/sec2ch.html';

use constant CM_SR_ST_FIRST_WRITE   => 1;
use constant CM_SR_ST_CONFIRM_WRITE => 2;
use constant CM_SR_ST_FINISH        => 3;
use constant CM_SR_ST_ERROR         => 4;
use constant CM_SR_ST_NINJA_MAKE    => 5;

sub _create_null_object {
    my $package = shift;
    my $methods = shift;
    my $self;
    eval  <<"__CODE__";
        package Null$package;

        \$self = {};
        bless \$self, 'Null$package';

        @{[ join("\n", map "sub $_ { $methods->{$_} }", keys %{$methods}) ]}
__CODE__
    return $self;
}

sub new {
    my $class = shift;
    my $param = shift;

    my $member = {
        cookie  => $param->{cookie} || {},
        cache   => $param->{cache}
            || _create_null_object('Cache', { exists => '', set => '' }),
        logger  => $param->{logger}
            || _create_null_object(
                'Logger',
                {
                    error => 'shift, die shift;',
                    warn  => $param->{strict} ? 'shift, die shift;' : 'shift, CORE::warn shift;',
                    debug => $ENV{DEBUG} ? 'shift, CORE::warn shift;' : '',
                }),
    };

    bless $member, $class;
}

sub _get_bbs_list_impl {
    my $self = shift;
    my @bbs_list;

    foreach (@{$self->_fetch_page(BBS_LIST_URL)}) {
        if (m|<A HREF=([^> ]+)>([^> ]+)</A>|) {
            push @bbs_list, { name => $2, url => $1 };
        }
    }
    return \@bbs_list;
}

sub get_bbs_list {
    my $self = shift;
    my $bbs_name = shift;

    my $bbs_list = $self->_get_bbs_list_impl();

    if (defined $bbs_name) {
        return (grep($_->{name} eq $bbs_name, @{$bbs_list}))[0];
    } else {
        return $bbs_list;
    }
}

sub _get_thread_list_impl {
    my $self = shift;
    my $bbs_name = shift;

    my $bbs_info = $self->get_bbs_list($bbs_name);
    my $url = URI->new(THREAD_LIST_FILE)->abs($bbs_info->{url});

    my @thread_list;
    foreach (@{$self->_fetch_page($url)}) {
        if (m|^(\d+)\.dat<>(.*)$|) {
            my ($id, $title) = ($1, $2);
            my ($sub_domain, $bbs_name)
                = ($bbs_info->{url} =~ m|^http://([^.]+)\.2ch\.net/([^/]+)/|);

            push @thread_list, {
                title => $title,
                url => sprintf(THREAD_URL_FORMAT, $sub_domain, $bbs_name, $id)
            };
        }
    }

    if (scalar(@thread_list) == 0) {
        $self->{logger}->warn(sprintf('thread list is empty'));
    }

    return \@thread_list;
}

sub get_thread_list {
    my $self = shift;
    my $bbs_name = shift;
    my $thread_keyword = shift;

    my $thread_list = $self->_get_thread_list_impl($bbs_name);

    if (defined $thread_keyword) {
        return [ grep($_->{title} =~ m|\Q$thread_keyword\E|, @{$thread_list}) ];
    } else {
        return $thread_list;
    }
}

sub _util_parse_charset {
    my $content = shift;

    return ($content =~ m|<meta http-equiv=["']?Content-Type["']? .*?charset=["']?([^"']+)["']?>|i)[0];
}

sub _write_comment_impl {
    my $self = shift;
    my $robot = shift;
    my $thread_url = shift;
    my $comment = shift;

    for (my $i = 0; $i < GET_RETRY_COUNT; $i++) {
        $self->{logger}->debug(sprintf('fetch %s', $thread_url));
        $robot->get($thread_url);

        if (!$robot->success()) {
            select(undef, undef, undef, WAIT_SEC);
            next;
        }

        my $content = $robot->content();

        # handle '<base>'
        my $base = ($content =~ m|<base\s+href=["']?([^"']+)["']?>|i)[0];
        if (!defined $base) {
            $base = $robot->base();
        } elsif ($base !~ m|^http|) {
            $base = URI->new_abs($base, $robot->base())->as_string();
        }
        $content =~ s|(<form method=["']?POST["']? action=["']?)([^"']+)(["']?>)|
            $1 . URI->new_abs($2, $base)->as_string(). $3|egi;
        $robot->update_html($content);

        # NOTE: expected form
        # --------------------------------------------------------------------
        # <form method=POST action="../test/bbs.cgi?guid=ON">
        # <input type=submit value="書き込む" name=submit>
        # 名前： <input name=FROM size=19>
        # E-mail<font size=1> (省略可) </font>: <input name=mail size=19><br>
        # <textarea rows=5 cols=70 wrap=off name=MESSAGE></textarea>
        # <input type=hidden name=bbs value=pav>
        # <input type=hidden name=key value=1345392283>
        # <input type=hidden name=time value=1104688508>
        # </form>
        # --------------------------------------------------------------------

        my $form = $robot->form_number(1);

        $form->value('FROM', $comment->{name});
        $form->value('mail', $comment->{mail});
        $form->value('MESSAGE', $comment->{body});
        $form->accept_charset(_util_parse_charset($content));

        $robot->request($form->click());

        if (!$robot->success()) {
            select(undef, undef, undef, WAIT_SEC);
            next;
        }
        return;
    }
}

sub _write_comment_first {
    my $self = shift;
    my $robot = shift;
    my $thread_url = shift;
    my $comment = shift;

    $self->{logger}->debug('first');

    $self->_write_comment_impl($robot, $thread_url, $comment);

    my $title = $robot->title();
    if ($title =~ m|■ 書き込み確認 ■|) {
        return CM_SR_ST_CONFIRM_WRITE;
    } elsif ($title =~ m|書きこみました。|) {
        return CM_SR_ST_FINISH;
    } else {
        $self->{logger}->error(sprintf('Unknown state: "%s".', $title));
        return CM_SR_ST_ERROR;
    }
}

sub _write_comment_confirm {
    my $self = shift;
    my $robot = shift;

    $self->{logger}->debug('confirm');

    select(undef, undef, undef, WAIT_SEC);

    my $form = $robot->form_number(1);
    $form->accept_charset(_util_parse_charset($robot->content()));
    $robot->request($form->click());

    my $content = $robot->content();
    my $title = $robot->title();
    if ($content =~ m|忍法帖を作成|) {
        $self->{logger}->debug('wait 120');
        select(undef, undef, undef, 120);

        return CM_SR_ST_FIRST_WRITE;
    } elsif ($content =~ m|やられたでござる|) {
        $self->{logger}->error(sprintf('HAMON! Wait for few hours.'));
        return CM_SR_ST_ERROR;
    } elsif ($title =~ m|書きこみました。|) {
        return CM_SR_ST_FINISH;
    } else {
        $self->{logger}->error(sprintf('Unknown state: "%s".', $robot->title()));
        return CM_SR_ST_ERROR;
    }
}

sub write_comment {
    my $self = shift;
    my $thread_url = shift;
    my $comment = shift;

    my $robot = WWW::Mechanize->new();
    $robot->cookie_jar($self->{cookie});

    my $state = CM_SR_ST_FIRST_WRITE;
    for (my $i = 0; $i < GET_RETRY_COUNT; $i++) {
         switch ($state) {
             case CM_SR_ST_FIRST_WRITE {
                 $state = $self->_write_comment_first($robot, $thread_url, $comment);
             }
             case CM_SR_ST_CONFIRM_WRITE {
                 $state = $self->_write_comment_confirm($robot);
             }
             case CM_SR_ST_FINISH {
                 return 0;
             }
             case CM_SR_ST_ERROR {
                 return -1;
             }
             else {
                 die 'BUG';
             }
         }
    }
}

sub get_comment_list {
    my $self = shift;
    my $thread = shift;

    my ($server, $bbs, $thread_id) = ($thread->{url} =~ m|http://([^/]+)/test/read.cgi/([^/]+)/([^/]+)/|);
    my $dat_url = sprintf('http://%s/%s/dat/%s.dat', $server, $bbs, $thread_id);

    my $date_parser = DateTime::Format::Strptime->new(
        time_zone => 'Asia/Tokyo',
        locale    => 'ja_JP',
        pattern => '%Y/%m/%d(%a) %H:%M:%S',
    );

    my @comment_list;
    foreach (@{$self->_fetch_page($dat_url)}) {
        my ($name, $mail, $date_str, $body) = split(m|<>|);
        my $date = $date_parser->parse_datetime($date_str);
        push @comment_list, {
            name => $name,
            mail => $mail,
            date => $date,
            body => $body,
        };
    }
    return \@comment_list;
}

sub _fetch_page {
    my $self = shift;
    my $url = shift;

    $self->{logger}->debug(sprintf('fetch %s', $url));

    if ($self->{cache}->exists($url)) {
        return split(/\n/, decode('utf8', $self->{cache}->get($url)));
    }
    my $robot = WWW::Mechanize->new();
    # FIXME: DRY
    for (my $i = 0; $i < GET_RETRY_COUNT; $i++) {
        select(undef, undef, undef, WAIT_SEC);
        $robot->get($url);

        next unless $robot->success();

        my $content = $robot->content();
        $content = utf8::is_utf8($content) ? $content : decode('Guess', $content);
        $self->{cache}->set($url, encode('utf8', $content));

        return [split(/\n/, $content)];
    }
    $self->{logger}->error(sprintf('FAILED to fetch: %s.', $url));
    return [];
}

1;
__END__

# Local Variables:
# mode: cperl
# coding: utf-8-unix
# End:
