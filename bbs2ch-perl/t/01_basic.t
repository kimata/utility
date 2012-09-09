#!/usr/bin/env perl
# Copyright (C) 2012 Tetsuya Kimata <kimata@green-rabbit.net>.

use utf8;
use open qw/:utf8 :std/;

use strict;
use warnings;

use Test::Most tests => 8;

use Data::Dumper;
use BBS::2ch;

use constant TEST_TARGET_BBS    => 'ニュース二軍+';
use constant TEST_TARGET_THREAD => '【政治】';

my $bbs_2ch = BBS::2ch->new({
#    cache  => $cache,
#    logger => get_logger(),
});

my ($thread_list, $comment_list);

# get_bbs_list
lives_ok { $bbs_2ch->get_bbs_list() } 'get list of BBS';

# get_bbs_info (with name)
cmp_deeply(
    $bbs_2ch->get_bbs_list(TEST_TARGET_BBS),
    {
        name => TEST_TARGET_BBS,
        url => re('^http://'),
    },
    'get information of specific BBS'
);

# get_thread_list
$thread_list = $bbs_2ch->get_thread_list(TEST_TARGET_BBS);
cmp_deeply(
    $thread_list,
    array_each({
        title => re('.+'),
        url => re('^http://'),
    }),
    'get list of threads in BBS'
);

# get_thread_list (with keyword)
$thread_list = $bbs_2ch->get_thread_list(TEST_TARGET_BBS, TEST_TARGET_THREAD);
ok(scalar(@{$thread_list}) != 0, 'get list of threads whose name matches the keyword (1)');
cmp_deeply(
    $thread_list,
    array_each({
        title => re(quotemeta(TEST_TARGET_THREAD)),
        url => re('^http://'),
    }),
    'get list of threads whose name matches the keyword (2)'
);

# get_comment_list
$comment_list = $bbs_2ch->get_comment_list($thread_list->[0]);
ok(scalar(@{$thread_list}) != 0, 'get list of comments in a specific thread (1)');
cmp_deeply(
    $comment_list,
    array_each({
        name => re('.+'),
        mail => ignore(),
        date => isa('DateTime'),
        body => re('.+'),
    }),
    'get list of comments in a specific thread (1)'
);

# write thread comment
ok($bbs_2ch->write_comment($thread_list->[0]->{url},
                           {
                               name => 'てすと',
                               mail => 'sage',
                               body => 'てすとです．てすとです．'
                           }) == 0,
   'wirite comment');

done_testing;

# Local Variables:
# mode: cperl
# coding: utf-8-unix
# End:
