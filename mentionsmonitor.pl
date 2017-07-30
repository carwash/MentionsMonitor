#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use 5.022;
use autodie qw(:file);
use open qw(:utf8 :std);

use AnyEvent::Twitter::Stream;
use Net::Twitter;
use Time::Moment;
use Try::Tiny;
use YAML::XS qw(DumpFile LoadFile);

# MentionsMonitor: A simple Twitter bot that scans for misdirected mentions and blocks the unwitting users.
# Inspired by @denny's MentionsManager <https://github.com/denny/MentionsManager>
my $VERSION = '1.03';

################################################################################

# Read in config and set up Net::Twitter for the REST API:
my ($nt, %oauth);
if (-e -f -s -r -w './oauth.yml') {
	%oauth = %{LoadFile('./oauth.yml')} or die "Failed to read Twitter OAuth file: $!\n";
}
else {
	die "Could not find/read Twitter OAuth file: $!\n";
}

if (exists $oauth{consumer_key} && defined $oauth{consumer_key} &&
    exists $oauth{consumer_secret} && defined $oauth{consumer_secret}) {
	$nt = Net::Twitter->new(
	                        traits          => [qw(API::RESTv1_1 OAuth RetryOnError)],
	                        consumer_key    => $oauth{consumer_key},
	                        consumer_secret => $oauth{consumer_secret},
	                       );
}
else {
	die "Could not find Twitter OAuth consumer key!\n";
}

if (exists $oauth{access_token} && defined $oauth{access_token} &&
    exists $oauth{access_token_secret} && defined $oauth{access_token_secret}) {
	$nt->access_token($oauth{access_token});
	$nt->access_token_secret($oauth{access_token_secret});
}

# If the client is not yet authorized, do it now:
unless ($nt->authorized) {
	say join(' ', 'Authorise this app at', $nt->get_authorization_url, 'and enter the PIN#:');
	my $pin = <STDIN>; # Wait for input
	chomp $pin;
	@oauth{qw(access_token access_token_secret user_id screen_name)} = $nt->request_access_token(verifier => $pin);
	$nt->access_token($oauth{access_token});
	$nt->access_token_secret($oauth{access_token_secret});
	say join(' ', 'Authorised user', $oauth{screen_name}, '.');
	DumpFile('./oauth.yml', \%oauth) or die "Failed to write Twitter OAuth file: $!\n";
}

unless (exists $oauth{user_id} && defined $oauth{user_id} &&
        exists $oauth{screen_name} && defined $oauth{screen_name}) {
	die "Could not find Twitter user id/screen name!\n"; # Suppose we could fetch it with $nt->verify_credentials but… really?
}

# Set up the AE::T::S listener for the streaming API:
my $finished = AnyEvent->condvar;
my $listener = AnyEvent::Twitter::Stream->new(
                                              consumer_key    => $oauth{consumer_key},
                                              consumer_secret => $oauth{consumer_secret},
                                              token           => $oauth{access_token},
                                              token_secret    => $oauth{access_token_secret},
                                              method          => 'filter',
                                              track           => '@'.$oauth{screen_name}, # Stream only tweets mentioning this user.
                                              on_tweet        => sub { # A tweet! A tweet!
	                                                                  my $tweet = shift;

	                                                                  # Must be a mention:
	                                                                  return if ($tweet->{text} !~ /\@${oauth{screen_name}}([\p{Zs}\.]|$)/ni);

	                                                                  # Must not match white-list rules:
	                                                                  return if (whitelist($nt, $tweet, $oauth{user_id}));

	                                                                  # If tweet matches block-list rules, block the user and log it:
	                                                                  if (blocklist($tweet, $oauth{screen_name})) {
		                                                                  if (block($nt, $tweet)) {
			                                                                  logblock($tweet);
		                                                                  }
		                                                                  else {
			                                                                  warn join(' ', 'ERROR: Attempt to block user', $tweet->{user}{screen_name}, "failed.\n");
		                                                                  }
	                                                                  }

	                                                                  return;
                                                                  },
                                              on_error        => sub {
	                                                                  my $error = shift;
	                                                                  warn "ERROR: $error\n";
	                                                                  $finished->send;
                                                                  },
                                              on_eof          => sub {
	                                                                  $finished->send;
                                                                  },
                                             ); # Streaming is ready; this is the main event loop.

$finished->recv;
# Exeunt omnes, laughing.

################################################################################

# White-list rules. Returns true if there is some existing relationship with the user and they should not be blocked.
sub whitelist {
	my ($nt, $tweet, $user_id) = @_;

	# Is the user, in fact, us?
	return 1 if ($user_id eq $tweet->{user}{id_str});

	# Does the user follow us, or do we follow the user? Are they already blocked?
	my $relationship = try {
		$nt->show_friendship({source_id => $user_id,
		                      target_id => $tweet->{user}{id_str},
		                     });
	} catch {
		warn join(' ', 'Error fetching relationship date on user', "$tweet->{user}{screen_name}.", $_->code, $_->message, $_->error, "\n");
		return undef;
	};
	
	return 1 if (defined $relationship &&
	             ($relationship->{source}{followed_by} ||
	              $relationship->{source}{following}   ||
	              $relationship->{source}{blocking})
	            );
	return 1 unless (defined $relationship); # If there was an error, err on the side of false negatives.

	# No? I suppose we don't know them, then.
	return 0;
}

# Block-list rules. Returns true if the tweet looks like it may have been misdirected.
sub blocklist {
	my ($tweet, $screen_name) = @_;

	# Is our username a substring of theirs?
	return 1 if ($tweet->{user}{screen_name} =~ /${screen_name}/i);

	# Do they sound like they might be an utter cockwomble?
	for (@{$tweet->{user}}{qw/name description/}) {
		return 1 if ($_ =~ /(?<![🚫🤜👊])[🐸🥛👌👌🏻卍卐](?![🤛👊])/);
	}

	my ($car, $wash) = ('[🚌🚍🚐🚕🚖🚗🚘🚙🚚🚛🚜]', '[💧💦☔️🚿🛀🛁]'); # Set of "car wash" emojis
	for (
	     # Does the tweet contain any "car wash" emojis?
	     qr/(${car}${wash}|${wash}${car})/n,
	     # Does the tweet consist soley of the mention, possibly with whitespace and/or other usernames?
	     qr/^([\p{Zs}\.]*\@[a-zA-Z0-9_]+[\p{Zs}\.]*)*[\p{Zs}\.]*\@${screen_name}([\p{Zs}\.]*\@[a-zA-Z0-9_]+[\p{Zs}\.]*)*[\p{Zs}\.]*$/ni,
	     # Is somebody <verb>ing at the carwash? Do they have company? Are they doing something with their car there?
	     qr/(chillin[g']?|sittin[g']?|waitin[g']?|workin[g']?|alone|on my own|with (my )?[a-zA-Z0-9_@]+|I( a|')m|(we|they)( a|')re|(wi|')ll be|car) \@${screen_name}/ni,
	     qr/\@${screen_name} (chillin[g']?|waitin[g']?|alone|on my own|with )/ni,
	     # Are they overly attached to their car?
	     qr/my baby/i,
	    ) {
		return 1 if ($tweet->{text} =~ /${_}/i);
	}

	# Is the tweet from Southeast Asia? (For some reason a lot of my misdirected mentions seem to be!)
	if (exists $tweet->{place} && defined $tweet->{place}) {
		for (qw(country full_name name)) {
			return 1 if (exists $tweet->{place}{$_} &&
			             defined $tweet->{place}{$_} &&
			             ($tweet->{place}{$_} =~ /(malaysia|kuala lumpur|johor|ipoh|brunei|begawan|philippines|quezon|calamba|manila|pampanga|indonesia|jakarta|surabaya|bandung|bekasi)/ni)
			            );
		}
	}

	# No? I suppose it seems legit, then.
	return 0;
}

# Block the user:
sub block {
	my ($nt, $tweet) = @_;

	my $blocked = try {
		$nt->create_block({user_id => $tweet->{user}{id_str}});
		return 1;
	} catch {
		warn join(' ', 'Error blocking user', "$tweet->{user}{screen_name}.", $_->code, $_->message, $_->error, "\n");
		return 0;
	};
	return $blocked;
}

# If the block worked, log it to a Markdown list for future reference:
sub logblock {
	my $tweet = shift;
	my $tm = Time::Moment->now_utc;
	open (my $log, '>>', './blocks.txt');
	printf ($log "- %s :: User [%s](https://www.twitter.com/%s) was blocked for tweet <https://www.twitter.com/%s/status/%s>\n", $tm->strftime('%Y-%m-%dT%H:%M:%S%Z'), $tweet->{user}{screen_name}, $tweet->{user}{screen_name}, $tweet->{user}{screen_name}, $tweet->{id_str});
	close $log;
	return;
}
