#!/usr/bin/perl
#
# Copyright © 2017 Duane Meyer <duane.meyer@gmail.com>
# Copyright © 2014 Jamie Zawinski <jwz@jwz.org> - https://www.jwz.org/hacks/twit-backup.pl
#
# Permission to use, copy, modify, distribute, and sell this software and its
# documentation for any purpose is hereby granted without fee, provided that
# the above copyright notice appear in all copies and that both that
# copyright notice and this permission notice appear in supporting
# documentation.  No representations are made about the suitability of this
# software for any purpose.  It is provided "as is" without express or
# implied warranty.
#
# Back story: (If you're interested)
# Impetus came from finding Unfavorable Semicircle (via jwz's blog)
# that led to finding a subreddit /r/unfavorablesemicircle and eventually
# to a loose knit community working this puzzle. Looking for deeper meaning.
# For a good primer check the reddit and also the wiki:
#     http://www.unfavorablesemicircle.com/wiki/Main_Page
#
# Long story longer - twitter (most likely thanks to gnip) makes it difficult
# to pull back all the tweets for a user after the latest 3500 or so.
# @unfavorablesemi has (as of April 2017) 94,845! Most are lost to the ether UNLESS
# one manages to find the twitter id.
#
# related:
#	https://www.reddit.com/r/UnfavorableSemicircle/comments/6j2d54/clawing_back_missing_data_from_twitter
# 

use POSIX;
use Net::Twitter;
use Data::Dumper;
use Math::BigInt;
use diagnostics;
use open ":encoding(utf8)";

my $progname = $0; $progname =~ s@.*/@@g;
my $verbose = 0;
my $debug = 0;

$|++; #"Buffers are for schmucks!" -some schmuck

# mksuf generates a list of low order bits for use in generating potentially valid twitter tweet ids (snowflakes)
# For tweet id format see:  https://github.com/twitter/snowflake/tree/snowflake-2010
my @suffixes = &mksuf();

# Twitter epoch used for calculating tweetids
# Same as Unix time. Nanosecond resolution. (might be microseconds)
my $twepoch = Math::BigInt->new("1288834974657");

# Generated searchorder worker, datacenter, sequence (inner -> outer)
sub mksuf() {
   my @ret; my $suf = "";
   for (my $seq=0; $seq<=20; $seq++) {
      for (my $dc=10; $dc<=11; $dc++) { 
         for (my $work=0; $work<=31; $work++) {
            $bindc = sprintf "%05b", $dc;
            $binwork = sprintf "%05b", $work;
            $binseq = sprintf "%012b", $seq;
            $binsuf = $bindc.$binwork.$binseq;
            #print "$binsuf\n";
            #@ret = (@ret, $binsuf);
            push @ret,$binsuf;
         }
      }
   }
   return @ret;
}

# list maker helper - generates partial or full lists of snowflakes as needed
sub _mklist($$$$$) {
   my $start = Math::BigInt->new(shift);
   my ($from, $until, $ms, $offset) = @_;
   my @search;
   for (my $i=$from; $i<=$until; $i++) {
      $flake = freeze($start + $offset + $ms, $suffixes[$i]);
      push @search,$flake;
   }
   return (@search);
}

# Generate a list of 100 tweet ids based off
#  the last known tweet id and mean time between tweets
sub mklist($$$$$) {
   my $start = Math::BigInt->new(shift);
   my ($mtbt, $ms, $suf, $offset) = @_;
   my @search;
   my $from = $suf;
   my $until = $suf + 99;
   if ($until > $#suffixes) {
      # finish out this round, search now has < 100 tweetIds
      print "First call to _mklist($start,$from,$#suffixes,$ms,$offset)\n" if ($verbose > 1);
      @search = _mklist($start,$from,$#suffixes,$ms,$offset);
      $suf = 0;
      $ms++;
      if ($ms > $mtbt) {
         $offset += $mtbt;
         $ms = 0 unless ($mtbt==0);
      }
      $until = 98-$#search;
      $suf = $until;
      print "2nd call to _mklist($start,0,$until,$ms,$offset)\n" if ($verbose > 1);
      @search = (@search, _mklist($start,0,$until,$ms,$offset));
   } else {
      $suf = $until+1;
      print "calling _mklist($start,$from,$until,$ms,$offset)\n" if ($verbose > 1);
      @search = _mklist($start,$from,$until,$ms,$offset);
   }
   return (\@search,$ms,$suf,$offset)
}

#form snowflake from given elements
sub freeze($$) {
   my $timestamp = Math::BigInt->new(shift @_);
   my $extra = shift @_;
   $timestamp = $timestamp - $twepoch;
   $tsbits = $timestamp->as_bin();
   $retval = $tsbits.$extra;
   return Math::BigInt->new($retval);
}

#decompose a snowflake into its parts
sub melt($) {
   $snowflake = Math::BigInt->new(shift @_);
   $sfbits = $snowflake->as_bin();
   $sfbits = substr $sfbits,-60;
   $bints = substr $sfbits,0,38;
   $bindc = substr $sfbits,38,5;
   $binwk = substr $sfbits,43,5;
   $binsq = substr $sfbits,48;
   $timestamp = Math::BigInt->new("0b$bints");
   $timestamp = $timestamp + $twepoch;
   $datactrId = Math::BigInt->new("0b$bindc");
   $workerId = Math::BigInt->new("0b$binwk");
   $seqId = Math::BigInt->new("0b$binsq");
   return ($timestamp,$datactrId,$workerId,$seqId);
}

sub error($) {
   my ($err) = @_;
   print STDERR "$progname: $err\n";
   exit 1;
}

sub load_keys($) {
  my ($user) = @_;

  my ($consumer_key, $consumer_secret, $token, $token_secret);

  # Read our twitter tokens
  error ("no \$HOME") unless defined($ENV{HOME});
  my $twitter_pass_file = "$ENV{HOME}/.$user-twitter-pass";
  if (open (my $in, '<', $twitter_pass_file)) {
    print STDERR "$progname: read $twitter_pass_file\n" if ($verbose > 1);
    while (<$in>) {
      s/#.*$//s;
      if (m/^\s*$/s) {
      } elsif (m/^consumer_key\s*[=:]\s*(.*?)\s*$/si) {
        $consumer_key = $1;
      } elsif (m/^consumer_secret\s*[=:]\s*(.*?)\s*$/si) {
        $consumer_secret = $1;
      } elsif (m/^token\s*[=:]\s*(.*?)\s*$/si) {
        $token = $1;
      } elsif (m/^token_secret\s*[=:]\s*(.*?)\s*$/si) {
        $token_secret = $1;
      } else {
        error ("$twitter_pass_file: unparsable line: $_");
      }
    }
    close $in;
  }

  error("no access tokens in $twitter_pass_file\n\n" .
         "\t\trun: $progname --generate-session\n")
    unless ($consumer_key && $consumer_secret && $token && $token_secret);

  return ($consumer_key, $consumer_secret, $token, $token_secret);
}

sub twit_generate_session($) {
  my ($user) = @_;

  print STDOUT ("1) Go here: https://dev.twitter.com/apps\n" .
   "   Click on the name of the app that you created.\n" .
   "   It should have the same name as your Twitter account (\"$user\").\n" .
   "\n" .
   "2) On the \"Settings\" tab, make sure that the \"Application Type\" is\n" .
   "   \"Read, Write and Access direct messages\".  If it isn't, change\n" .
   "   it, then go to the \"Details\" tab and click \"Recreate my access\n" .
   "   token\".  Hit reload until you see the change take effect.\n" .
   "\n" .
   "3) Go to the \"Details\" tab.  Enter the \"Consumer key\" here: "
   );

  my $consumer_key = <>;
  chomp ($consumer_key);
  error ("That's not a consumer key: \"$consumer_key\"")
    unless ($consumer_key =~ m/^[-_a-zA-Z0-9]{16,}$/s);

  print STDOUT "4) Enter the \"Consumer Secret\" here: ";
  my $consumer_secret = <>;
  chomp ($consumer_secret);
  error ("That's not a consumer secret: \"$consumer_secret\"")
    unless ($consumer_secret =~ m/^[-_a-zA-Z0-9]{40,}$/s);

  print STDOUT "5) Enter the \"Access token\" here: ";
  my $token = <>;
  chomp ($token);
  error ("That's not an access token: \"$token\"")
    unless ($token =~ m/^[-_a-zA-Z0-9]{40,}$/s);

  print STDOUT "6) Enter the \"Access token secret\" here: ";
  my $token_secret = <>;
  chomp ($token_secret);
  error ("That's not an access token secret: \"$token_secret\"")
    unless ($token_secret =~ m/^[-_a-zA-Z0-9]{40,}$/s);

  my $fn = $ENV{HOME} . "/.$user-twitter-pass";
  my $body = '';
 if (open (my $in, '<', $fn)) {
    local $/ = undef;  # read entire file
    $body = <$in>;
    close $in;
  }

  $body .= "CONSUMER_KEY:\t $consumer_key\n"
    unless ($body =~ s/^((CONSUMER_KEY)[ \t]*[=:][ \t]*)([^\n]*)/$1$consumer_key/mi);
  $body .= "CONSUMER_SECRET: $consumer_secret\n"
    unless ($body =~ s/^((CONSUMER_SECRET)[ \t]*[=:][ \t]*)([^\n]*)/$1$consumer_secret/mi);
  $body .= "TOKEN:\t\t $token\n"
    unless ($body =~ s/^((TOKEN)[ \t]*[=:][ \t]*)([^\n]*)/$1$token/mi);
  $body .= "TOKEN_SECRET:\t $token_secret\n"
    unless ($body =~ s/^((TOKEN_SECRET)[ \t]*[=:][ \t]*)([^\n]*)/$1$token_secret/mi);

  open (my $out, '>', $fn) || error ("$fn: $!");
  print $out $body;
  close $out;

  system ("chmod", "og-rw", $fn);

  print STDOUT "\nDone!  $fn has been updated with your\n" .
               "new access tokens.  Keep them secret.\n\n";
}

sub twit_lookup($$$$$) {
   my ($user,$start,$ms,$suf,$mtbt) = @_;

   my ($consumer_key, $consumer_secret, $token, $token_secret) = load_keys($user);

   my $nt = Net::Twitter->new(
      traits   => [qw/OAuth API::RESTv1_1 WrapError/],
      ssl      => 1,
      consumer_key        => $consumer_key,
      consumer_secret     => $consumer_secret,
      access_token        => $token,
      access_token_secret => $token_secret,
   );

   my $found = 0;
   my $checked = 0;
   my $count = 0;
   my $oldcount = 0;
   my $nochct = 0;
   my $offset = $mtbt;
   while (!$found) {
      my ($search,$newms,$newsuf,$newoffset) = mklist($start,$mtbt,$ms,$suf,$offset);
      @foo = @$search;
      $checked += $#foo+1; # ye olde O.B.O.E. (count from 0 or 1?)
      $ms=$newms; $suf=$newsuf; $offset=$newoffset;
      $s = join(',', @$search);
      
      print $s if ($verbose > 2);
      if (!$debug) {
         $ret = undef;
         do {
            $ret = $nt->lookup_statuses({ id => $s });
            sleep 10 unless $ret;
         } until $ret;
      }

      for my $tweet (@$ret) {
         my $twitdump = Dumper($tweet);
         if ($twitdump =~ m/^.*(unfavorablesemi|unfavorable.semi|707046313469333504).*$/mi) {
            print "OMG LOOK!!! -->";
         }
         open(LOGIT,">","saved/$tweet->{id}.txt");
         print LOGIT $twitdump;
         close LOGIT;
         print "$tweet->{id},$tweet->{user}{screen_name}\n";
         $count++;
      }

      print "suf=$suf, ms=$ms, checked=$checked, redirects=$count\n";
      sleep 5 unless $debug; # limited by app request limit :(
   } #endwhile
} #endsub

sub usage() {
  print STDERR "usage: $progname [--verbose] [--debug] [--tweet id] [-t TIME(ms)] [-s SUFFIX] [-i INTERVAL(ms)]\n";
  print STDERR "usage: $progname --generate-session\n";
  exit 1;
}

sub main() {
   # Last known tweet ID in EL series - searching forward from here for EL70
   my $startid = Math::BigInt->new("707072909689397248");
   my $mtbt = "49000"; # mean time between tweets (in millisecs)
   my $ms=0; # ms before/after mtbt SINCE the last tweet
   my $suf=0;
   my $user = "2nd";
   my $gen_p = undef;
   while ($#ARGV >= 0) {
      $_ = shift @ARGV;
      if (m/^--?verbose$/) { $verbose++; }
      elsif (m/^-t$/) { $ms = shift @ARGV; }
      elsif (m/^-s$/) { $suf = shift @ARGV; }
      elsif (m/^-i$/) { $mtbt = shift @ARGV; }
      elsif (m/^-v+$/) { $verbose += length($_)-1; }
      elsif (m/^--?tweet$/) { $a = shift @ARGV; $startid = Math::BigInt->new($a); }
      elsif (m/^--?debug$/) { $debug++; }
      elsif (m/^--?gen(erate(-session)?)?$/) { $gen_p = 1; }
      elsif (m/^-./) { usage(); }
      else { usage(); }
   }

   my ($start,$dc,$worker,$seq) = melt($startid);
   if ($gen_p) {
      twit_generate_session($user);
   } elsif ($debug==1) {
      testing($user,$mtbt,$start);
   } else {
      print "Starting search from tweetid: $a\n";
      twit_lookup($user, $start, $ms, $suf, $mtbt);
   }
}

main();
exit 0;

# testing rate_limit
sub testing($$$) {
   my ($user, $mtbt, $start) = @_;

   my ($consumer_key, $consumer_secret, $token, $token_secret) = load_keys($user);
#   ($a,$b,$c,$d) = melt('707075464058109956');
#  ($e,undef,undef,undef) = melt('707075760930947076');

#   print "$a,$b,$c,$d,$e\n";

  # print "$consumer_key, $consumer_secret, $token, $token_secret\n";
   $ms=41969; $suf=116; $offset=42019; $mtbt=42019;
   ($search,$newms,$newsuf,$newoffset) = mklist($start,$mtbt,$ms,$suf,$offset);
   print join(',',@$search);
   print "\n$ms -> $newms, $suf -> $newsuf, $offset -> $newoffset\n";
   @foo = @$search;
   print "$#foo\n";
   $ms=42000; $suf=116; $offset=42019; $mtbt=42019;
   ($search,$newms,$newsuf,$newoffset) = mklist($start,$mtbt,$ms,$suf,$offset);
   print join(',',@$search);
   print "\n$ms -> $newms, $suf -> $newsuf, $offset -> $newoffset\n";
   @foo = @$search;
   print "$#foo\n";
   $ms=42000; $suf=493; $offset=42019; $mtbt=42019;
   ($search,$newms,$newsuf,$newoffset) = mklist($start,$mtbt,$ms,$suf,$offset);
   print join(',',@$search);
   print "\n$ms -> $newms, $suf -> $newsuf, $offset -> $newoffset\n";
   @foo = @$search;
   print "$#foo\n";
   exit;
   
   my $nt = Net::Twitter->new(
      traits   => [qw/OAuth API::RESTv1_1 WrapError/],
      ssl      => 1,
      consumer_key        => $consumer_key,
      consumer_secret     => $consumer_secret,
      access_token        => $token,
      access_token_secret => $token_secret,
   );

   $ret = $nt->lookup_statuses({ id => '707060725135646721' });
   print Dumper($ret);
   exit 1;
   
   print "I am authorized as a user!\n" if ( $nt->authorized );
   $ret = $nt->lookup_statuses({ id => '707060725135646721,707062302009368576,707073239999119363,707073245778870275,707072934880395267' });
   $count = 0;
   for my $tweet (@$ret) {
      if (Dumper($tweet) =~ m/^.*(unfavorablesemi|unfavorable.semi|707046313469333504).*$/mi) {
         print "OMG LOOK!!! -->";
         open(LOGIT,">","saved/$tweet->{id}.txt");
         print LOGIT Dumper($tweet);
         close LOGIT;
      }
      print "$tweet->{id},$tweet->{user}{screen_name},$tweet->{user}{id}\n";
      $count++;
#      print Dumper($tweet);
   }

   exit;

   my $ret = $nt->rate_limit_status();
   my $app_until = $ret->{resources}->{application}->{'/application/rate_limit_status'}->{reset};
   my $app_remains = $ret->{resources}->{application}->{'/application/rate_limit_status'}->{remaining};
   my $app_limit = $ret->{resources}->{application}->{'/application/rate_limit_status'}->{limit};
   my $user_until = $ret->{resources}->{statuses}->{'/statuses/lookup'}->{reset};
   my $user_remains = $ret->{resources}->{statuses}->{'/statuses/lookup'}->{remaining};
   my $user_limit = $ret->{resources}->{statuses}->{'/statuses/lookup'}->{limit};
   my $now = `date +%s`; chomp $now;
   print "Before loop\n";
   print "App--limit: $app_limit, remains: $app_remains, now: $now, app_until: $app_until, diff: ",($app_until - $now),"\n";
   print "User--limit: $user_limit, remains: $user_remains, now: $now, user_until: $user_until, diff: ",($user_until - $now),"\n";
   #error($nt->http_message) unless $ret;
   #print Dumper($ret);
   #exit;
   for ($i=0; $i<10; $i++) {
      $ret = $nt->lookup_statuses({ id => '707073239999119363,707073245778870275,707072934880395267' });
      print "Looping: ".$i." ";
   }
   $ret = $nt->rate_limit_status();
   $app_until = $ret->{resources}->{application}->{'/application/rate_limit_status'}->{reset};
   $app_remains = $ret->{resources}->{application}->{'/application/rate_limit_status'}->{remaining};
   $app_limit = $ret->{resources}->{application}->{'/application/rate_limit_status'}->{limit};
   $user_until = $ret->{resources}->{statuses}->{'/statuses/lookup'}->{reset};
   $user_remains = $ret->{resources}->{statuses}->{'/statuses/lookup'}->{remaining};
   $user_limit = $ret->{resources}->{statuses}->{'/statuses/lookup'}->{limit};
   $now = `date +%s`; chomp $now;
   print "After loop\n";
   print "App--limit: $app_limit, remains: $app_remains, now: $now, app_until: $app_until, diff: ",($app_until - $now),"\n";
   print "User--limit: $user_limit, remains: $user_remains, now: $now, user_until: $user_until, diff: ",($user_until - $now),"\n";

   exit;

   my $lim = $ret->{resources}->{statuses}->{'/statuses/lookup'}->{remaining};
   print $lim."\n";

   $ms=48996; $suf=1; $offset=49000;
   (@search,$newms,$newsuf) = mklist($start,$mtbt,$ms,$suf,$offset);
   print $search;
   print "\n$ms -> $newms, $suf -> $newsuf\n";

   exit 1;
}
